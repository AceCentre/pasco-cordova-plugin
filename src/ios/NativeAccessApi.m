//
//  NativeAccessApi.m
//  AUDScan
//
//  Created by Hossein Amin on 5/22/17.
//
//

#import "NativeAccessApi.h"
#import <AVFoundation/AVFoundation.h>

@interface NAAFinishCallbackData : NSObject

@property (nonatomic) AVSpeechSynthesizer *synthesizer;
@property (nonatomic) AVSpeechUtterance *utterance;
@property (nonatomic) NSString *callbackId;

+ (NAAFinishCallbackData*)dataWithSynthesizer:(AVSpeechSynthesizer*)synthesizer utterance:(AVSpeechUtterance*)utterance callbackId:(NSString*)callbackId;

@end

@implementation NAAFinishCallbackData

+ (NAAFinishCallbackData*)dataWithSynthesizer:(AVSpeechSynthesizer*)synthesizer utterance:(AVSpeechUtterance*)utterance callbackId:(NSString*)callbackId {
    NAAFinishCallbackData *data = [[NAAFinishCallbackData alloc] init];
    data.utterance = utterance;
    data.synthesizer = synthesizer;
    data.callbackId = callbackId;
    return data;
}

@end

@interface NativeAccessApi () <AVSpeechSynthesizerDelegate>

@end

@implementation NativeAccessApi {
    NSMutableDictionary *_pointers;
    NSMutableArray *_finish_callbacks;
    bool _isSoftKeyboardVisible;
}

- (void)pluginInitialize {
    [super pluginInitialize];
    _pointers = [[NSMutableDictionary alloc] init];
    _finish_callbacks = [[NSMutableArray alloc] init];
    _isSoftKeyboardVisible = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    NSDictionary* userInfo = [notification userInfo];
    CGRect keyboardFrame = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboard = [self.viewController.view convertRect:keyboardFrame fromView:self.viewController.view.window];
    CGFloat height = self.viewController.view.frame.size.height;
    @synchronized (self) {
        _isSoftKeyboardVisible = (keyboard.origin.y + keyboard.size.height) <= height;
    }
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    @synchronized (self) {
        _isSoftKeyboardVisible = NO;
    }
}

- (void)dispose {
    [super dispose];
    _pointers = nil;
    _finish_callbacks = nil;
}

+ (NSString*)mkNewKeyForDict:(NSMutableDictionary*)dict {
    NSString *key;
    NSInteger trylen = 5;
    do {
        if(trylen == 0) {
            [[NSException exceptionWithName:@"TRYLEN EXCEED" reason:@"try length for new key exceeded" userInfo:nil] raise];
            break;
        }
        key = [[NSProcessInfo processInfo] globallyUniqueString];
        trylen -= 1;
    } while([dict objectForKey:key] != nil);
    return key;
}

- (id)pointerObjectForKey:(NSString*)key excepting:(Class)cls canBeNull:(Boolean)canBeNull error:(NSString**)error {
    id ptr;
    @synchronized (self) {
        ptr = [_pointers objectForKey:key];
    }
    if(ptr == nil) {
        *error = [NSString stringWithFormat:@"Excepting object of type %@ is nil", NSStringFromClass(cls)];
        return nil;
    }
    if(![ptr isKindOfClass:cls]) {
        *error = [NSString stringWithFormat:@"Excepting object of type %@ but %@ is given", NSStringFromClass(cls), NSStringFromClass([ptr class])];
        return nil;
    }
    return ptr;
}

- (void)request_audio_record_permission:(CDVInvokedUrlCommand*)command {
  [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
      [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:granted] callbackId:command.callbackId];
    }];
}

- (void)has_synthesizer:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES] callbackId:command.callbackId];
}
- (void)has_audio_device:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES] callbackId:command.callbackId];
}

- (void)is_software_keyboard_visible:(CDVInvokedUrlCommand*)command {
    bool value;
    @synchronized (self) {
        value = _isSoftKeyboardVisible;
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:value] callbackId:command.callbackId];
}

- (void)get_voices:(CDVInvokedUrlCommand*)command {
    NSMutableArray *voices = [NSMutableArray new];
    for(AVSpeechSynthesisVoice *voice in [AVSpeechSynthesisVoice speechVoices]) {
        [voices addObject:@{
                            @"id": voice.identifier,
                            @"label": voice.name
                            }];
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:voices] callbackId:command.callbackId];
}

- (void)init_synthesizer:(CDVInvokedUrlCommand*)command {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        AVSpeechSynthesizer *speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
        speechSynthesizer.delegate = self;
        NSString *key;
        @synchronized (self) {
            key = [NativeAccessApi mkNewKeyForDict:_pointers];
            [_pointers setObject:speechSynthesizer forKey:key];
        }
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:key] callbackId:command.callbackId];
    });
}
- (void)init_utterance:(CDVInvokedUrlCommand*)command {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *speech = [command.arguments objectAtIndex:0];
        AVSpeechUtterance *speechUtterance = [[AVSpeechUtterance alloc] initWithString:speech];
        
        NSDictionary *options = command.arguments.count > 1 ?
        [command.arguments objectAtIndex:1] : nil;
        if([options isKindOfClass:[NSDictionary class]]) {
            NSString *voiceId = [options objectForKey:@"voiceId"];
            if([voiceId isKindOfClass:[NSString class]]) {
                AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voiceId];
                if(voice != nil) {
                    speechUtterance.voice = voice;
                }
            }
            NSNumber *num;
            
            num = [options objectForKey:@"volume"];
            if([num isKindOfClass:[NSNumber class]]) {
                speechUtterance.volume = [num floatValue];
            }
            
            num = [options objectForKey:@"pitch"];
            if([num isKindOfClass:[NSNumber class]]) {
                speechUtterance.pitchMultiplier = [num floatValue];
            }
            
            NSString *rate = [options objectForKey:@"rate"];
            num = [options objectForKey:@"rateMul"];
            if([rate isKindOfClass:[NSString class]] ||
               [num isKindOfClass:[NSNumber class]]) {
                float rateVal = 1.0f;
                if([rate isEqualToString:@"default"]) {
                    rateVal = AVSpeechUtteranceDefaultSpeechRate;
                } else if([rate isEqualToString:@"min"]) {
                    rateVal = AVSpeechUtteranceMinimumSpeechRate;
                } else if([rate isEqualToString:@"max"]) {
                    rateVal = AVSpeechUtteranceMaximumSpeechRate;
                }
                if([num isKindOfClass:[NSNumber class]])
                    rateVal *= [num floatValue];
                speechUtterance.rate = rateVal;
            }
            
            num = [options objectForKey:@"delay"];
            if([num isKindOfClass:[NSNumber class]]) {
                speechUtterance.preUtteranceDelay = (NSTimeInterval)[num longValue] / 1000.0;
            }
        }
        
        NSString *key;
        @synchronized (self) {
            key = [NativeAccessApi mkNewKeyForDict:_pointers];
            [_pointers setObject:speechUtterance forKey:key];
        }
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:key] callbackId:command.callbackId];
    });
}
- (void)release_synthesizer:(CDVInvokedUrlCommand*)command {
    @synchronized (self) {
        [_pointers removeObjectForKey:[command.arguments objectAtIndex:0]];
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}
- (void)release_utterance:(CDVInvokedUrlCommand*)command {
    @synchronized (self) {
        [_pointers removeObjectForKey:[command.arguments objectAtIndex:0]];
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}
- (void)speak_utterance:(CDVInvokedUrlCommand*)command {
    NSString *synKey = [command.arguments objectAtIndex:0];
    NSString *uttKey = [command.arguments objectAtIndex:1];
    CDVPluginResult *result;
    NSString *error = nil;
    AVSpeechSynthesizer *speechSynthesizer = [self pointerObjectForKey:synKey excepting:[AVSpeechSynthesizer class] canBeNull:NO error:&error];
    AVSpeechUtterance *speechUtterance = [self pointerObjectForKey:uttKey excepting:[AVSpeechUtterance class] canBeNull:NO error:&error];
    if(speechSynthesizer == nil || speechUtterance == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
    } else {
        [speechSynthesizer speakUtterance:speechUtterance];
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}
- (void)stop_speaking:(CDVInvokedUrlCommand*)command {
    NSString *synKey = [command.arguments objectAtIndex:0];
    CDVPluginResult *result;
    NSString *error = nil;
    AVSpeechSynthesizer *speechSynthesizer = [self pointerObjectForKey:synKey excepting:[AVSpeechSynthesizer class] canBeNull:NO error:&error];
    if(speechSynthesizer == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
    } else {
        [speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}
- (void)speak_finish:(CDVInvokedUrlCommand*)command {
    NSString *synKey = [command.arguments objectAtIndex:0];
    NSString *uttKey = [command.arguments objectAtIndex:1];
    NSString *error = nil;
    AVSpeechSynthesizer *speechSynthesizer = [self pointerObjectForKey:synKey excepting:[AVSpeechSynthesizer class] canBeNull:NO error:&error];
    AVSpeechUtterance *speechUtterance = [self pointerObjectForKey:uttKey excepting:[AVSpeechUtterance class] canBeNull:NO error:&error];
    if(speechSynthesizer == nil || speechUtterance == nil) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error] callbackId:command.callbackId];

    } else {
        [_finish_callbacks addObject:[NAAFinishCallbackData dataWithSynthesizer:speechSynthesizer utterance:speechUtterance callbackId:command.callbackId]];
    }
}

- (void)applyFinishFor:(AVSpeechSynthesizer*)synthesizer utterance:(AVSpeechUtterance*)utterance {
    for (NSUInteger i = 0; i < [_finish_callbacks count]; ) {
        NAAFinishCallbackData *data = [_finish_callbacks objectAtIndex:i];
        if(data.synthesizer == synthesizer && data.utterance == utterance) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:data.callbackId];
            [_finish_callbacks removeObjectAtIndex:i];
        } else {
            i++;
        }
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    [self applyFinishFor:synthesizer utterance:utterance];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    [self applyFinishFor:synthesizer utterance:utterance];
}

@end


