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

#define NES_HAS_TRAINER 1 << 2

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
    
    // Skip trainer
    if (flags_6 & NES_HAS_TRAINER) {
        prg_rom_offset += 512;
    }
    
    NSLog(@"Create section of %d bytes at [0x%x;0x%x[", 16 * 1024, 0x8000, 0x8000 + 0x4000);

    NSObject<HPSegment> *prg_rom_segment = [file addSegmentAt:0x8000 size:0x8000];
    prg_rom_segment.segmentName = @"PRG_ROM";
    // NSString *comment = [NSString stringWithFormat:@"\n\nBank %d\n\n", x];

    NSData *segmentData = [NSData dataWithBytes:&bytes[prg_rom_offset] length:0x8000];
    prg_rom_segment.mappedData = segmentData;
    prg_rom_segment.fileOffset = prg_rom_offset;
    prg_rom_segment.fileLength = 0x8000;

    // this should be "prg_rom_units" instead of "2", but we don't know how to swap banks.
    int nb_sections = 2;
    
    // max(prg_rom_units, 2)
    if (prg_rom_units < nb_sections)
        nb_sections = prg_rom_units;
    
    for (int x = 0; x < nb_sections; x++) {
        uint32_t startAddress = 0x8000 + (0x4000 * x);
        
        NSObject<HPSection> *section = [prg_rom_segment addSectionAt:startAddress size:0x4000];
        
        NSString *sectionName = [NSString stringWithFormat:@"Bank %d", x];
        section.sectionName = sectionName;
        section.pureCodeSection = YES;
        
        section.fileOffset = prg_rom_offset + 0x4000 * x;
        section.fileLength = 0x4000;
    }
    
    // NSObject<HPSegment> *chr_rom_segment = [file addSegmentAt:0x8000 size:0x8000];

    file.cpuFamily = @"ricoh";
    file.cpuSubFamily = @"R2A03";
    [file setAddressSpaceWidthInBits:32];
    [file addEntryPoint:0x8000];
    
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
