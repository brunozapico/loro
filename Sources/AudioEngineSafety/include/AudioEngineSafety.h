#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
/// AVAudioEngine raises Objective-C exceptions for some device-change races;
/// Swift do/catch cannot catch them. Keep the throwing calls on this side.
AVAudioFormat * _Nullable LoroAudioInputFormat(AVAudioEngine *engine);
BOOL LoroStartAudioEngine(AVAudioEngine *engine, AVAudioNodeTapBlock tap,
                         NSError * _Nullable * _Nullable error);
void LoroStopAudioEngine(AVAudioEngine *engine);
NS_ASSUME_NONNULL_END
