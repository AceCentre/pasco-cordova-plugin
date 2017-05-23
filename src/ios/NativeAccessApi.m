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
}

- (void)pluginInitialize {
    [super pluginInitialize];
    _pointers = [[NSMutableDictionary alloc] init];
    _finish_callbacks = [[NSMutableArray alloc] init];
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
    id ptr = [_pointers objectForKey:key];
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

- (void)has_synthesizer:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES] callbackId:command.callbackId];
}
- (void)has_audio_device:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES] callbackId:command.callbackId];
}
- (void)init_synthesizer:(CDVInvokedUrlCommand*)command {
    AVSpeechSynthesizer *speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
    speechSynthesizer.delegate = self;
    NSString *key = [NativeAccessApi mkNewKeyForDict:_pointers];
    [_pointers setObject:speechSynthesizer forKey:key];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:key] callbackId:command.callbackId];
}
- (void)init_utterance:(CDVInvokedUrlCommand*)command {
    NSString *speech = [command.arguments objectAtIndex:0];
    AVSpeechUtterance *speechUtterance = [[AVSpeechUtterance alloc] initWithString:speech];
    speechUtterance.rate = AVSpeechUtteranceDefaultSpeechRate;
    NSString *key = [NativeAccessApi mkNewKeyForDict:_pointers];
    [_pointers setObject:speechUtterance forKey:key];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:key] callbackId:command.callbackId];
}
- (void)release_synthesizer:(CDVInvokedUrlCommand*)command {
    [_pointers removeObjectForKey:[command.arguments objectAtIndex:0]];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}
- (void)release_utterance:(CDVInvokedUrlCommand*)command {
    [_pointers removeObjectForKey:[command.arguments objectAtIndex:0]];
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
