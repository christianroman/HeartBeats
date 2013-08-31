//
//  MainViewController.m
//  HeartBeats
//
//  Created by Christian Roman on 30/08/13.
//  Copyright (c) 2013 Christian Roman. All rights reserved.
//

#import "MainViewController.h"

@interface MainViewController ()
{
    AVCaptureSession *session;
    CALayer* imageLayer;
    NSMutableArray *points;
}

@end

@implementation MainViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    imageLayer = [CALayer layer];
    imageLayer.frame = self.view.layer.bounds;
    imageLayer.contentsGravity = kCAGravityResizeAspectFill;
    [self.view.layer addSublayer:imageLayer];
    
    [self setupAVCapture];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self stopAVCapture];
}

- (void)setupAVCapture
{
    // Get the default camera device
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if([device isTorchModeSupported:AVCaptureTorchModeOn]) {
		[device lockForConfiguration:nil];
		device.torchMode=AVCaptureTorchModeOn;
        [device setTorchMode:AVCaptureTorchModeOn];
		[device unlockForConfiguration];
	}
    
	// Create the AVCapture Session
	session = [AVCaptureSession new];
    [session beginConfiguration];
    
	// Create a AVCaptureDeviceInput with the camera device
	NSError *error = nil;
	AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if (error) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Error %d", (int)[error code]]
                                                            message:[error localizedDescription]
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
        [alertView show];
        //[self teardownAVCapture];
        return;
    }
    
    if ([session canAddInput:deviceInput])
		[session addInput:deviceInput];
    
    // AVCaptureVideoDataOutput
    
    AVCaptureVideoDataOutput *videoDataOutput = [AVCaptureVideoDataOutput new];
	NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
									   [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	[videoDataOutput setVideoSettings:rgbOutputSettings];
	[videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
	dispatch_queue_t videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
	[videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    
    if ([session canAddOutput:videoDataOutput])
		[session addOutput:videoDataOutput];
    AVCaptureConnection* connection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoMinFrameDuration:CMTimeMake(1, 10)];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    [session commitConfiguration];
    [session startRunning];
}

- (void)stopAVCapture
{
    [session stopRunning];
    session = nil;
    points = nil;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    uint8_t *buf = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    float r = 0, g = 0,b = 0;
	for(int y = 0; y < height; y++) {
		for(int x = 0; x < width * 4; x += 4) {
			b += buf[x];
			g += buf[x+1];
			r += buf[x+2];
		}
		buf += bytesPerRow;
	}
	r /= 255 * (float)(width * height);
	g /= 255 * (float)(width * height);
	b /= 255 * (float)(width * height);
    
	float h,s,v;
	RGBtoHSV(r, g, b, &h, &s, &v);
	static float lastH = 0;
	float highPassValue = h - lastH;
	lastH = h;
	float lastHighPassValue = 0;
	float lowPassValue = (lastHighPassValue + highPassValue) / 2;
	lastHighPassValue = highPassValue;
    
    [self render:context value:[NSNumber numberWithFloat:lowPassValue]];
    
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    id renderedImage = CFBridgingRelease(quartzImage);
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [CATransaction setDisableActions:YES];
        [CATransaction begin];
		imageLayer.contents = renderedImage;
        [CATransaction commit];
	});
}

- (void)render:(CGContextRef)context value:(NSNumber *)value
{
    if(!points)
        points = [NSMutableArray new];
    [points insertObject:value atIndex:0];
    CGRect bounds = imageLayer.bounds;
	while(points.count > bounds.size.width / 2)
		[points removeLastObject];
    if(points.count == 0)
        return;
    
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, 2);
    CGContextBeginPath(context);
    
    CGFloat scale = [[UIScreen mainScreen] scale];
    
    // Flip coordinates from UIKit to Core Graphics
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, .0f, bounds.size.height);
    CGContextScaleCTM(context, scale, scale);
    
    float xpos = bounds.size.width * scale;
    float ypos = [[points objectAtIndex:0] floatValue];
    
    CGContextMoveToPoint(context, xpos, ypos);
    for(int i = 1; i < points.count; i++) {
        xpos -= 5;
        float ypos = [[points objectAtIndex:i] floatValue];
        CGContextAddLineToPoint(context, xpos, bounds.size.height / 2 + ypos * bounds.size.height / 2);
    }
    CGContextStrokePath(context);
    
    CGContextRestoreGState(context);
}

void RGBtoHSV( float r, float g, float b, float *h, float *s, float *v ) {
	float min, max, delta;
	min = MIN( r, MIN(g, b ));
	max = MAX( r, MAX(g, b ));
	*v = max;
	delta = max - min;
	if( max != 0 )
		*s = delta / max;
	else {
		*s = 0;
		*h = -1;
		return;
	}
	if( r == max )
		*h = ( g - b ) / delta;
	else if( g == max )
		*h = 2 + (b - r) / delta;
	else
		*h = 4 + (r - g) / delta;
	*h *= 60;
	if( *h < 0 )
		*h += 360;
}

@end
