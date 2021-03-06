#import "NativeOscillator.h"
#import <AudioToolbox/AudioToolbox.h>

double __frequency = 880;
double __theta = 0;
double __sampleRate = 44100;
int tri_theta = 1;

OSStatus RenderToneSine(
												void *inRefCon,
												AudioUnitRenderActionFlags *ioActionFlags,
												const AudioTimeStamp *inTimeStamp,
												UInt32 inBusNumber,
												UInt32 inNumberFrames,
												AudioBufferList *ioData)
{
	// Fixed amplitude is good enough for our purposes
	const double amplitude = 0.25;
	
	double theta = __theta;
	double theta_increment = 2.0 * M_PI * __frequency / __sampleRate;
	
	// This is a mono tone generator so we only need the first buffer
	const int channel = 0;
	Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
	
	// Generate the samples
	for (UInt32 frame = 0; frame < inNumberFrames; frame++)
	{
		buffer[frame] = sin(theta) * amplitude;
		
		theta += theta_increment;
		if (theta > 2.0 * M_PI)
		{
			theta -= 2.0 * M_PI;
		}
	}
	
	__theta = theta;
	
	return noErr;
}

OSStatus RenderToneTriangle(
														void *inRefCon,
														AudioUnitRenderActionFlags *ioActionFlags,
														const AudioTimeStamp *inTimeStamp,
														UInt32 inBusNumber,
														UInt32 inNumberFrames,
														AudioBufferList *ioData) {
	// x = m - abs(i % (2*m) - m)
	
	const double amplitude = 0.15;
	const int channel = 0;
	double theta = __theta;
	double period = 2.0;
	const double theta_increment = __frequency / __sampleRate;
	Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
	
	for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
		buffer[frame] = amplitude * (1.0 - fabs(fmod(theta, period) - 0.5*period));
		
		theta += theta_increment;
		
		if (theta >= period) {
			theta = 0;
		}
	}
	
	__theta = theta;
	
	return noErr;
}

void ToneInterruptionListener(void *inClientData, UInt32 inInterruptionState)
{
}

@implementation NativeOscillator
RCT_EXPORT_MODULE();

- (void)createToneUnit
{
	// Configure the search parameters to find the default playback output unit
	// (called the kAudioUnitSubType_RemoteIO on iOS but
	// kAudioUnitSubType_DefaultOutput on Mac OS X)
	AudioComponentDescription defaultOutputDescription;
	defaultOutputDescription.componentType = kAudioUnitType_Output;
	defaultOutputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	defaultOutputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	defaultOutputDescription.componentFlags = 0;
	defaultOutputDescription.componentFlagsMask = 0;
	
	// Get the default playback output unit
	AudioComponent defaultOutput = AudioComponentFindNext(NULL, &defaultOutputDescription);
	NSAssert(defaultOutput, @"Can't find default output");
	
	// Create a new unit based on this that we'll use for output
	OSErr err = AudioComponentInstanceNew(defaultOutput, &toneUnit);
	NSAssert1(toneUnit, @"Error creating unit: %id", err);
	
	// Set our tone rendering function on the unit
	AURenderCallbackStruct input;
	input.inputProc = RenderToneTriangle;
	input.inputProcRefCon = (__bridge void * _Nullable)(self);
	err = AudioUnitSetProperty(toneUnit,
														 kAudioUnitProperty_SetRenderCallback,
														 kAudioUnitScope_Input,
														 0,
														 &input,
														 sizeof(input));
	NSAssert1(err == noErr, @"Error setting callback: %id", err);
	
	// Set the format to 32 bit, single channel, floating point, linear PCM
	const int four_bytes_per_float = 4;
	const int eight_bits_per_byte = 8;
	AudioStreamBasicDescription streamFormat;
	streamFormat.mSampleRate = __sampleRate;
	streamFormat.mFormatID = kAudioFormatLinearPCM;
	streamFormat.mFormatFlags =
	kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
	streamFormat.mBytesPerPacket = four_bytes_per_float;
	streamFormat.mFramesPerPacket = 1;
	streamFormat.mBytesPerFrame = four_bytes_per_float;
	streamFormat.mChannelsPerFrame = 1;
	streamFormat.mBitsPerChannel = four_bytes_per_float * eight_bits_per_byte;
	err = AudioUnitSetProperty (toneUnit,
															kAudioUnitProperty_StreamFormat,
															kAudioUnitScope_Input,
															0,
															&streamFormat,
															sizeof(AudioStreamBasicDescription));
	NSAssert1(err == noErr, @"Error setting stream format: %id", err);
}

RCT_EXPORT_METHOD(play:(nonnull NSNumber *)frequency)
{
	if (toneUnit)
	{
		AudioOutputUnitStop(toneUnit);
		AudioUnitUninitialize(toneUnit);
		AudioComponentInstanceDispose(toneUnit);
		
		toneUnit = nil;
	}
	else
	{
		[self createToneUnit];
		
		__frequency = [frequency doubleValue];
		__theta = 0.25;
		
		// Stop changing parameters on the unit
		OSErr err = AudioUnitInitialize(toneUnit);
		NSAssert1(err == noErr, @"Error initializing unit: %ld", err);
		
		// Start playback
		err = AudioOutputUnitStart(toneUnit);
		NSAssert1(err == noErr, @"Error starting unit: %ld", err);
	}
}

RCT_EXPORT_METHOD(stop)
{
	if (toneUnit)
	{
		[self play:0];
	}
}

- (id)init {
	__sampleRate = 44100;
	
	OSStatus result = AudioSessionInitialize(NULL, NULL, ToneInterruptionListener, (__bridge void *)(self));
	if (result == kAudioSessionNoError)
	{
		UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
		AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);
	}
	AudioSessionSetActive(true);
	
	return self;
}

- (void)dealloc {
	AudioSessionSetActive(false);
}

@end
