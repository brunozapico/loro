#import "AudioEngineSafety.h"

AVAudioFormat *LoroAudioInputFormat(AVAudioEngine *engine) {
    @try { return [engine.inputNode outputFormatForBus:0]; }
    @catch (NSException *exception) { return nil; }
}

void LoroStopAudioEngine(AVAudioEngine *engine) {
    @try {
        [engine stop];
        [engine.inputNode removeTapOnBus:0];
    } @catch (NSException *exception) {
        // A disconnected device may already have torn down the I/O node.
    }
}

BOOL LoroStartAudioEngine(AVAudioEngine *engine, AVAudioNodeTapBlock tap, NSError **error) {
    @try {
        // Let the engine choose the current format; hardware can change after
        // the caller queried it. Swift rejects mismatched callback buffers.
        [engine.inputNode installTapOnBus:0 bufferSize:4096 format:nil block:tap];
        [engine prepare];
        if ([engine startAndReturnError:error]) return YES;
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"com.brunozapico.loro.audio"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey:
                                               @"The audio device changed or became unavailable."}];
    }
    LoroStopAudioEngine(engine);
    return NO;
}
