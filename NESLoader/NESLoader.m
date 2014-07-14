//
//  NESLoader.m
//  NESLoader
//
//  Created by bcharron on 2014-07-13.
//  Copyright (c) 2014 Benjamin Charron. All rights reserved.
//

#import "NESLoader.h"

// "NES" with DOS EOF
#define NES_MAGIC 0x1A53454E
#define NES_HAS_SRAM 1 << 4
#define NES_HAS_TRAINER 1 << 2

#define NES_MAPPER_MMC1 0x01

#define NES_NMI_VECTOR 0xFFFA
#define NES_RESET_VECTOR 0xFFFC
#define NES_IRQ_VECTOR 0xFFFE

@implementation NESLoader {
    NSObject<HPHopperServices> *_services;
}

- (instancetype)initWithHopperServices:(NSObject<HPHopperServices> *)services {
    if (self = [super init]) {
        _services = services;
    }
    return self;
}

- (UUID *)pluginUUID {
    return([_services UUIDWithString:@"d402b3e0-0adb-11e4-9191-0800200c9a66"]);
}

- (HopperPluginType)pluginType {
    return(Plugin_Loader);
}

- (NSString *)pluginName {
    return(@"NES File");
}

- (NSString *)pluginDescription {
    return(@"NES File Loader");
}

- (NSString *)pluginAuthor {
    return(@"Benjamin Charron");
}

- (NSString *)pluginCopyright {
    return(@"Copyright (C) 2014 Benjamin Charron");
}

- (NSString *)pluginVersion {
    return(@"0.1.0");
}


- (BOOL)canLoadDebugFiles {
    return(NO);
}

/// Returns an array of DetectedFileType objects.
- (NSArray *)detectedTypesForData:(NSData *)data {
    const void *bytes = (const void *)[data bytes];
    if (OSReadLittleInt32(bytes, 0) == NES_MAGIC) {
        NSObject<HPDetectedFileType> *type = [_services detectedType];
        [type setFileDescription:@"NES Cartridge"];
        [type setAddressWidth:AW_32bits];
        [type setCpuFamily:@"ricoh"];
        [type setCpuSubFamily:@"R2A03"];
        return @[type];
    }
    return (@[]);
}

- (void)createCodeSegment:(NSString *)name  atVirtualAddress:(Address)virtualAddress atFileOffset:(Address)fileOffset length:(size_t)length  forFile:(NSObject<HPDisassembledFile> *)file withData:(NSData *)data {

    const uint8_t *bytes = (const uint8_t *)[data bytes];
    
    NSString *segCreated = [NSString stringWithFormat:@"Create segment of %ld bytes at $%04llX-$%04llX", length, virtualAddress, virtualAddress + length - 1];
    [_services logMessage:segCreated];
    
    NSObject<HPSegment> *segment = [file addSegmentAt:virtualAddress size:length];
    segment.segmentName = @"PRG_ROM_BANK1";
    
    NSData *segmentData = [NSData dataWithBytes:&bytes[fileOffset] length:length];
    segment.mappedData = segmentData;
    segment.fileOffset = fileOffset;
    segment.fileLength = length;
    
    NSObject<HPSection> *section = [segment addSectionAt:virtualAddress size:length];
    
    section.sectionName = name;
    section.containsCode = YES;
    
    section.fileOffset = fileOffset;
    section.fileLength = length;
    
}


/// Load a file.
/// The plugin should create HPSegment and HPSection objects.
/// It should also fill information about the CPU by setting the CPU family, the CPU subfamily and optionally the CPU plugin UUID.
/// The CPU plugin UUID should be set ONLY if you want a specific CPU plugin to be used. If you don't set it, it will be later set by Hopper.
/// During long operations, you should call the provided "callback" block to give a feedback to the user on the loading process.
- (FileLoaderLoadingStatus)loadData:(NSData *)data usingDetectedFileType:(DetectedFileType *)fileType options:(FileLoaderOptions)options forFile:(NSObject<HPDisassembledFile> *)file usingCallback:(FileLoadingCallbackInfo)callback {
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    
    // Offset for the start of the PRG ROM
    uint32_t prg_rom_offset = 16;
    
    const uint8_t prg_rom_units = bytes[4];
    uint8_t chr_rom_units = bytes[5];
    uint8_t flags_6 = bytes[6];
    uint8_t flags_7 = bytes[7];
    uint8_t prg_ram_size = bytes[8];
    uint8_t flags_9 = bytes[9];
    uint8_t flags_10 = bytes[10];
    
    // Skip trainer if there is one
    if (flags_6 & NES_HAS_TRAINER) {
        prg_rom_offset += 512;
    }
    
    uint8_t mapper = (flags_7 & 0xF0) | ((flags_6 & 0xF0) >> 4);
    
    if (mapper != NES_MAPPER_MMC1) {
        NSLog(@"ERROR: Mapper %d is not supported.", mapper);
        return(DIS_NotSupported);
    } else {
        switch(mapper) {
            case NES_MAPPER_MMC1:
                [_services logMessage:@"Detected MMC1 mapper."];
                break;
                
            default:
                break;
        }
    }
    
    // Create a segment for the first bank, mapped at $8000 at powerup (?)
    [self createCodeSegment:@"Bank 0" atVirtualAddress:0x8000 atFileOffset:prg_rom_offset length:0x4000 forFile:file withData:data];

    
    // Create a segment for the last bank, which is mapped at $C000 at powerup
    int last_bank_offset = (prg_rom_units - 1) * 0x4000 + prg_rom_offset;
    
    NSString *sectionName = [NSString stringWithFormat:@"Bank %d", prg_rom_units - 1];
    
    [self createCodeSegment:sectionName atVirtualAddress:0xC000 atFileOffset:last_bank_offset length:0x4000 forFile:file withData:data];
    
    
    // SRAM - 0:present 1:not present
    if ((flags_10 & NES_HAS_SRAM) == 0) {
        [_services logMessage:@"This cartridge has SRAM in $6000-$7FFF"];
        
        NSObject<HPSegment> *sram_segment = [file addSegmentAt:0x6000 size:0x2000];
        sram_segment.segmentName = @"SRAM";
        
        NSObject<HPSection> *section = [sram_segment addSectionAt:0x6000 size:0x2000];
        section.sectionName = @"SRAM";
        section.pureDataSection = YES;
    }
    
    // Create RAM segment: $0000-$2000
    NSObject<HPSegment> *ram_segment = [file addSegmentAt:0x0000 size:0x2000];
    ram_segment.segmentName = @"RAM";
    
    NSObject<HPSection> *ram_section = [ram_segment addSectionAt:0x0000 size:0x2000];
    ram_section.sectionName = @"RAM";
    ram_section.pureDataSection = YES;
    
    // Create PPU Control Registers: $2000-$2008 (and mirrors 2009-3FFF)
    NSObject<HPSegment> *ppu_ctrl_registers_segment = [file addSegmentAt:0x2000 size:0x2000];
    ppu_ctrl_registers_segment.segmentName = @"PPUCTLREG";
    
    NSObject<HPSection> *ppu_ctrl_registers_section = [ppu_ctrl_registers_segment addSectionAt:0x2000 size:0x2000];
    ppu_ctrl_registers_section.sectionName = @"PPUCTLREG";
    ppu_ctrl_registers_section.pureDataSection = YES;
    
    [file setName:@"PPUCTRL" forVirtualAddress:0x2000];
    [file setName:@"PPUMASK" forVirtualAddress:0x2001];
    [file setName:@"PPUSTATUS" forVirtualAddress:0x2002];
    [file setName:@"OAMADDR" forVirtualAddress:0x2003];
    [file setName:@"OAMDATA" forVirtualAddress:0x2004];
    [file setName:@"PPUSCROLL" forVirtualAddress:0x2005];
    [file setName:@"PPUADDR" forVirtualAddress:0x2006];
    [file setName:@"PPUDATA" forVirtualAddress:0x2007];
    
    // Create APU Control Registers: $4000-$401F
    NSObject<HPSegment> *apu_reg_segment = [file addSegmentAt:0x4000 size:20];
    apu_reg_segment.segmentName = @"APUCTRLREG";
    
    NSObject<HPSection> *apu_reg_section = [ppu_ctrl_registers_segment addSectionAt:0x4000 size:20];
    apu_reg_section.sectionName = @"APUCTRLREG";
    apu_reg_section.pureDataSection = YES;

    
    // NSObject<HPSegment> *chr_rom_segment = [file addSegmentAt:0x8000 size:0x8000];

    file.cpuFamily = @"ricoh";
    file.cpuSubFamily = @"R2A03";
    [file setAddressSpaceWidthInBits:32];
    
    // Get the reset vector at 0xFFFC from the last bank
    uint16_t reset_vector = OSReadLittleInt16(bytes, last_bank_offset + 0x3FFC);
    uint16_t nmi_vector = OSReadLittleInt16(bytes, last_bank_offset + 0x3FFA);
    uint16_t irq_vector = OSReadLittleInt16(bytes, last_bank_offset + 0x3FFE);
    
    [file setName:@"nmi_vector" forVirtualAddress:NES_NMI_VECTOR];
    [file setName:@"reset_vector" forVirtualAddress:NES_RESET_VECTOR];
    [file setName:@"irq_vector" forVirtualAddress:NES_IRQ_VECTOR];
    
    [file setType:Type_Int16 atVirtualAddress:NES_NMI_VECTOR forLength:2];
    [file setType:Type_Int16 atVirtualAddress:NES_RESET_VECTOR forLength:2];
    [file setType:Type_Int16 atVirtualAddress:NES_IRQ_VECTOR forLength:2];
    
    [file addPotentialProcedure:nmi_vector];
    [file addPotentialProcedure:reset_vector];
    [file addPotentialProcedure:irq_vector];
    
    [file setFormat:Format_Address forArgument:0 atVirtualAddress:NES_NMI_VECTOR];
    [file setFormat:Format_Address forArgument:0 atVirtualAddress:NES_RESET_VECTOR];
    [file setFormat:Format_Address forArgument:0 atVirtualAddress:NES_IRQ_VECTOR];

    [file addEntryPoint:reset_vector];
    
    return(DIS_OK);
}

- (FileLoaderLoadingStatus)loadDebugData:(NSData *)data forFile:(NSObject<HPDisassembledFile> *)file usingCallback:(FileLoadingCallbackInfo)callback {
    return(DIS_NotSupported);
}

/// Extract a file
/// In the case of a "composite loader", extract the NSData object of the selected file.
- (NSData *)extractFromData:(NSData *)data
      usingDetectedFileType:(DetectedFileType *)fileType
         returnAdjustOffset:(uint64_t *)adjustOffset {
    return(nil);
}

@end
