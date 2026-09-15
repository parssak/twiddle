#import "DiscoOverlay.h"
#import "DiscoMotion.h"
#import "DiscoNowPlaying.h"
#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

typedef struct {
    // canvas: logical width, logical height, one device pixel in normalized
    // canvas coordinates, and 0 for beams / 1 for the native-resolution ball.
    vector_float4 canvas;
    // Logical top-left origin and size of this render pass within the screen.
    vector_float4 viewport;
    // Elapsed time, deployment, extra swipe rotation, and resting depth.
    vector_float4 timing;
    vector_float4 motion;
    vector_float4 album[4];
} DiscoUniforms;

// A reversible playhead keeps interrupted hovers continuous. The ball
// drops in after the initial .30-second dim, then springs into place.
static const double DiscoDimmingDuration = .30;
static const double DiscoDuration = 1.42;
static const float DiscoRestingDepth = .16f;
@interface DiscoAnimation : NSObject
- (float)deploymentAt:(CFTimeInterval)now;
- (double)setActive:(BOOL)active;
@property (readonly) CFTimeInterval startedAt;
@property (readonly) DiscoMotion *motion;
- (void)setAlbumColors:(NSArray<NSColor *> *)colors;
- (vector_float4)albumColor:(NSUInteger)index at:(double)time;
@end

@implementation DiscoAnimation {
    double _from;
    CFTimeInterval _changedAt;
    BOOL _active;
    NSArray<NSColor *> *_albumColors;
    vector_float4 _albumFrom[4], _albumTo[4];
    double _albumChangedAt;
}
- (instancetype)init {
    if ((self = [super init])) {
        _startedAt = _changedAt = CACurrentMediaTime();
        _motion = [DiscoMotion new];
    }
    return self;
}
- (vector_float4)albumColor:(NSUInteger)index at:(double)time {
    float t = fmax(0, fmin(1, (time-_albumChangedAt)/.8));
    t = t*t*(3-2*t);
    return simd_mix(_albumFrom[index], _albumTo[index], t);
}
- (void)setAlbumColors:(NSArray<NSColor *> *)colors {
    if ([_albumColors isEqualToArray:colors]) return;
    double now = CACurrentMediaTime();
    for (NSUInteger i=0;i<4;i++) {
        _albumFrom[i] = [self albumColor:i at:now];
        if (colors.count) {
            NSColor *color = colors[i % colors.count];
            _albumTo[i] = (vector_float4){color.redComponent,color.greenComponent,color.blueComponent,1};
            if (_albumFrom[i].w == 0) _albumFrom[i] = (vector_float4){color.redComponent,color.greenComponent,color.blueComponent,0};
        } else {
            _albumTo[i] = _albumFrom[i];
            _albumTo[i].w = 0;
        }
    }
    _albumColors = [colors copy];
    _albumChangedAt = now;
}
- (float)deploymentAt:(CFTimeInterval)now {
    double elapsed = now - _changedAt;
    return (float)fmax(0, fmin(DiscoDuration, _from + (_active ? elapsed : -elapsed)));
}
- (double)setActive:(BOOL)active {
    CFTimeInterval now = CACurrentMediaTime();
    _from = [self deploymentAt:now];
    _changedAt = now;
    _active = active;
    if (!active) [_motion reset];
    return active ? DiscoDuration - _from : _from;
}
@end

@interface DiscoPanel : NSPanel
@end
@implementation DiscoPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

static NSPoint discoBallCenter(DiscoAnimation *animation, NSRect screen, double now) {
    float drop = fmaxf(0, [animation deploymentAt:now]-DiscoDimmingDuration);
    float spring = expf(-4.2f*drop)*(cosf(9.5f*drop) + .442105f*sinf(9.5f*drop));
    float edge = fmaxf(0, fminf(1, (drop-.70f)/.25f));
    float fall = 1-spring*(1-edge*edge*(3-2*edge));
    vector_float2 offset = [animation.motion offsetAt:now];
    return NSMakePoint(NSMidX(screen)+offset.x*NSHeight(screen),
        NSMaxY(screen)-(-.035*1.8+(DiscoRestingDepth+.035*1.8)*fall+offset.y)*NSHeight(screen));
}

@interface DiscoBallView : MTKView
@property DiscoAnimation *animation;
@property NSScreen *discoScreen;
@property (readonly) BOOL trackingPull;
- (void)cancelPull;
@property (copy) void (^cancelHandler)(void);
@end
@implementation DiscoBallView {
    NSPoint _grabPoint;
    BOOL _moved;
    NSUInteger _hapticStep;
    double _lastHapticAt;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event {
    double now = CACurrentMediaTime();
    NSPoint point = [self.window convertPointToScreen:event.locationInWindow];
    NSPoint center = discoBallCenter(self.animation, self.discoScreen.frame, now);
    if (hypot(point.x-center.x, point.y-center.y) > NSHeight(self.discoScreen.frame)*.035*1.18) return;
    _grabPoint = point;
    _moved = NO;
    _hapticStep = 0;
    _lastHapticAt = 0;
    _trackingPull = YES;
    [self.animation.motion beginAt:now];
    [NSCursor.closedHandCursor set];
}
- (void)scrollWheel:(NSEvent *)event {
    // Apply only finger movement; our own friction replaces macOS scroll momentum.
    if (_trackingPull || !event.hasPreciseScrollingDeltas || event.momentumPhase != NSEventPhaseNone) return;
    double now = CACurrentMediaTime();
    NSPoint point = [self.window convertPointToScreen:event.locationInWindow];
    NSPoint center = discoBallCenter(self.animation, self.discoScreen.frame, now);
    if (hypot(point.x-center.x, point.y-center.y) > NSHeight(self.discoScreen.frame)*.035*1.18) return;
    double delta = fabs(event.scrollingDeltaX) >= fabs(event.scrollingDeltaY)
        ? event.scrollingDeltaX : event.scrollingDeltaY;
    if (event.isDirectionInvertedFromDevice) delta = -delta;
    [self.animation.motion addSpin:delta*.035 at:now];
}
- (void)mouseDragged:(NSEvent *)event {
    if (!_trackingPull || !self.animation.motion.dragging) return;
    NSPoint point = [self.window convertPointToScreen:event.locationInWindow];
    vector_float2 delta = {(float)(point.x-_grabPoint.x), (float)(_grabPoint.y-point.y)};
    if (simd_length(delta) > 3) _moved = YES;
    double now = CACurrentMediaTime();
    BOOL snapped = [self.animation.motion pull:delta/(float)NSHeight(self.discoScreen.frame) at:now];
    // Progress detents get denser near the latch; holding still never buzzes.
    static const float detents[] = {.18f, .36f, .52f, .66f, .78f, .88f, .95f};
    BOOL tick = NO;
    while (_hapticStep < sizeof(detents)/sizeof(detents[0]) &&
        self.animation.motion.pullProgress >= detents[_hapticStep]) {
        _hapticStep++;
        tick = YES;
    }
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"hapticsEnabled"] &&
        (snapped || (tick && now-_lastHapticAt >= .035))) {
        [NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:
            snapped ? NSHapticFeedbackPatternAlignment : NSHapticFeedbackPatternLevelChange
            performanceTime:NSHapticFeedbackPerformanceTimeNow];
        _lastHapticAt = now;
    }
}
- (void)cancelPull {
    if (_trackingPull) [NSCursor.arrowCursor set];
    _trackingPull = NO;
    [self.animation.motion reset];
}
- (void)mouseUp:(NSEvent *)event {
    if (!_trackingPull) return;
    _trackingPull = NO;
    [self.animation.motion releaseAt:CACurrentMediaTime()];
    [NSCursor.arrowCursor set];
    if (!_moved && self.cancelHandler) self.cancelHandler();
}
@end

@interface DiscoRenderer : NSObject <MTKViewDelegate>
- (instancetype)initWithPipeline:(id<MTLRenderPipelineState>)pipeline
                     commandQueue:(id<MTLCommandQueue>)commandQueue
                        animation:(DiscoAnimation *)animation
                           screen:(NSScreen *)screen
                         ballPass:(BOOL)ballPass;
@end

@implementation DiscoRenderer {
    id<MTLRenderPipelineState> _pipeline;
    id<MTLCommandQueue> _commandQueue;
    DiscoAnimation *_animation;
    NSScreen *_screen;
    BOOL _ballPass;
}
- (instancetype)initWithPipeline:(id<MTLRenderPipelineState>)pipeline
                     commandQueue:(id<MTLCommandQueue>)commandQueue
                        animation:(DiscoAnimation *)animation
                           screen:(NSScreen *)screen
                         ballPass:(BOOL)ballPass {
    if ((self = [super init])) {
        _pipeline = pipeline;
        _commandQueue = commandQueue;
        _animation = animation;
        _screen = screen;
        _ballPass = ballPass;
    }
    return self;
}
- (void)drawInMTKView:(MTKView *)view {
    MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!pass || !drawable) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (_ballPass) {
        DiscoBallView *ball = (DiscoBallView *)view;
        NSPoint center = discoBallCenter(_animation, _screen.frame, now);
        CGFloat padding = NSHeight(_screen.frame)*.049;
        NSRect frame = NSMakeRect(fmin(NSMidX(_screen.frame), center.x)-padding,
            center.y-padding, fabs(center.x-NSMidX(_screen.frame))+2*padding,
            fmax(2*padding, NSMaxY(_screen.frame)-center.y+padding));
        if (!NSEqualRects(view.window.frame, frame)) {
            [view.window setFrame:frame display:NO];
            view.drawableSize = NSMakeSize(NSWidth(view.bounds)*_screen.backingScaleFactor,
                NSHeight(view.bounds)*_screen.backingScaleFactor);
        }
        NSPoint mouse = NSEvent.mouseLocation;
        BOOL overBall = hypot(mouse.x-center.x, mouse.y-center.y) <= NSHeight(_screen.frame)*.035*1.18;
        view.window.ignoresMouseEvents = !ball.trackingPull && !overBall;
    }
    NSRect windowFrame = view.window.frame;
    vector_float4 viewport = {
        (float)(NSMinX(windowFrame) - NSMinX(_screen.frame)),
        (float)(NSMaxY(_screen.frame) - NSMaxY(windowFrame)),
        (float)NSWidth(windowFrame),
        (float)NSHeight(windowFrame),
    };
    float pointPerPixel = (float)(NSHeight(view.bounds) / fmax(view.drawableSize.height, 1.0));
    vector_float2 offset = [_animation.motion offsetAt:now];
    DiscoUniforms uniforms = {
        .canvas = {(float)NSWidth(_screen.frame), (float)NSHeight(_screen.frame),
            pointPerPixel / (float)NSHeight(_screen.frame), _ballPass ? 1.0f : 0.0f},
        .viewport = viewport,
        .timing = {(float)(now - _animation.startedAt), [_animation deploymentAt:now], (float)[_animation.motion spinAngleAt:now], DiscoRestingDepth},
        .motion = {offset.x, offset.y, (float)(_animation.motion.palette % 4), [_animation.motion paletteBlendAt:now]},
    };
    for (NSUInteger i=0;i<4;i++) uniforms.album[i] = [_animation albumColor:i at:now];
    id<MTLCommandBuffer> buffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:_pipeline];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}
@end

@interface DiscoOverlayController ()
@property NSMutableArray<DiscoPanel *> *windows;
@property NSMutableArray<DiscoRenderer *> *renderers;
@end

@implementation DiscoOverlayController {
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLCommandQueue> _commandQueue;
    DiscoAnimation *_animation;
    BOOL _visible;
    NSUInteger _transitionGeneration;
    id _escapeMonitor;
    DiscoNowPlaying *_nowPlaying;
}

static NSString *DiscoShaderSource(void) {
    return @"#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct Raster { float4 position [[position]]; float2 uv; };\n"
        "struct Uniforms { float4 canvas; float4 viewport; float4 timing; float4 motion; float4 album[4]; };\n"
        "vertex Raster discoVertex(uint id [[vertex_id]]) {\n"
        "  const float2 positions[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};\n"
        "  const float2 uvs[3] = {float2(0,1), float2(2,1), float2(0,-1)};\n"
        "  Raster out; out.position = float4(positions[id],0,1); out.uv = uvs[id]; return out;\n"
        "}\n"
        "float hash21(float2 p) { return fract(sin(dot(p,float2(127.1,311.7))) * 43758.5453); }\n"
        // Sample deterministic mirror cells from a periodic longitude grid.
        // Divergence widens each screen-clipped volume away from its source.
        "float3 fallbackTint(float i, int palette) {\n"
        "  float f=hash21(float2(i,31.0));\n"
        "  if (palette==1) return mix(float3(1,.18,.38),float3(1,.65,.12),f);\n"
        "  if (palette==2) return mix(float3(.12,.85,1),float3(.65,.25,1),f);\n"
        "  if (palette==3) return .55+.45*cos(6.2831853*(f+float3(0,.333,.667)));\n"
        "  return float3(1);\n"
        "}\n"
        "float3 beamTint(float i, int palette, constant Uniforms &u) {\n"
        "  if (palette!=0) return fallbackTint(i,palette);\n"
        "  int index=int(hash21(float2(i,31.0))*4.0);\n"
        "  float4 accent=u.album[index];\n"
        "  return mix(float3(1),accent.rgb,accent.a);\n"
        "}\n"
        "float3 beamField(float2 q, float rotation, float radius, float palette, float blend, constant Uniforms &u) {\n"
        "  float3 energy=float3(0.0);\n"
        "  const float longitudeCells=56.0;\n"
        "  const float longitudeDensity=longitudeCells/(2.0*3.14159265359);\n"
        "  for (int i=0;i<48;i++) {\n"
        "    float fi=float(i);\n"
        // Select real centers from the same periodic grid used to draw the
        // ball. Material longitude moves opposite the sampling offset.
        "    float latitudeCell=fmod(fi*11.0+3.0,31.0)-15.0;\n"
        "    float longitudeCell=fmod(fi*17.0+5.0,longitudeCells);\n"
        "    float latitude=(latitudeCell+0.5)/10.0;\n"
        "    float longitude=(longitudeCell+0.5)/longitudeDensity-rotation;\n"
        "    float latitudeRadius=cos(latitude);\n"
        "    float3 facetNormal=float3(sin(longitude)*latitudeRadius,sin(latitude),cos(longitude)*latitudeRadius);\n"
        "    float3 sourceDirection=normalize(float3(-0.60,-0.70,1.0));\n"
        "    float3 reflected=reflect(-sourceDirection,facetNormal);\n"
        "    float projectedLength=length(reflected.xy);\n"
        "    if (projectedLength<0.04) continue;\n"
        "    float2 beamDirection=reflected.xy/projectedLength;\n"
        "    float2 origin=facetNormal.xy*radius*0.82;\n"
        "    float2 local=q-origin;\n"
        "    float along=dot(local,beamDirection);\n"
        "    if (along<=0.0) continue;\n"
        "    float across=abs(local.x*beamDirection.y-local.y*beamDirection.x);\n"
        "    float divergence=0.012+hash21(float2(fi,9.0))*0.028;\n"
        "    float halfWidth=0.0015+max(0.0,along-radius)*divergence;\n"
        "    float core=1.0-smoothstep(halfWidth*0.10,halfWidth*0.36,across);\n"
        "    float body=1.0-smoothstep(halfWidth*0.30,halfWidth,across);\n"
        "    float haze=(1.0-smoothstep(halfWidth*0.75,halfWidth*2.6,across))*0.10;\n"
        "    float start=smoothstep(radius*0.95,radius*2.6,along);\n"
        "    float brightness=0.22+0.70*pow(hash21(float2(fi,13.0)),1.7);\n"
        "    float illumination=smoothstep(0.02,0.55,dot(facetNormal,sourceDirection));\n"
        "    float visibleFacet=smoothstep(-0.10,0.28,facetNormal.z);\n"
        "    float directionality=smoothstep(0.10,0.72,projectedLength);\n"
        "    float visibility=illumination*visibleFacet*directionality;\n"
        "    float volume=(core*0.40+body*0.22+haze)/(1.0+along*0.50);\n"
        "    float3 tint=mix(beamTint(fi,(int(palette)+3)%4,u),beamTint(fi,int(palette),u),blend); energy+=tint*volume*start*brightness*visibility;\n"
        "  }\n"
        "  return 1.0-exp(-energy*1.55);\n"
        "}\n"
        "fragment float4 discoFragment(Raster in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {\n"
        "  float2 canvasPosition=u.viewport.xy+in.uv*u.viewport.zw;\n"
        "  float2 uv=canvasPosition/u.canvas.xy; float aspect=u.canvas.x/max(u.canvas.y,1.0);\n"
        "  float t=u.timing.x; float deployment=u.timing.y; float drop=max(0.0,deployment-0.30);\n"
        "  float spring=exp(-4.2*drop)*(cos(9.5*drop)+0.442105*sin(9.5*drop));\n"
        "  float fall=1.0-spring*(1.0-smoothstep(0.70,0.95,drop));\n"
        "  float lamp=smoothstep(0.0,0.30,deployment); float radius=0.035;\n"
        "  float ballY=mix(-radius*1.8,u.timing.w,fall);\n"
        "  float rotation=t*0.30+u.timing.z;\n"
        "  float2 p=float2((uv.x-0.5)*aspect,uv.y); float2 center=float2(0,ballY)+u.motion.xy; float2 q=p-center;\n"
        "  bool ballPass=u.canvas.w>0.5;\n"
        "  float3 light=ballPass ? float3(0) : beamField(q,rotation,radius,u.motion.z,u.motion.w,u)*lamp*smoothstep(0.70,0.95,drop);\n"
        // Output is premultiplied: white light replaces part of the dimming,
        // avoiding the muddy grey produced by multiplying bright patches twice.
        "  float dimAlpha=ballPass ? 0.0 : 0.78*lamp;\n"
        "  float3 color=float3(light);\n"
        "  float alpha=dimAlpha+max(light.r,max(light.g,light.b))*(1.0-dimAlpha);\n"
        "  float pixel=u.canvas.z;\n"
        "  if (ballPass) {\n"
        "    float2 stringEnd=center-normalize(center)*radius*.95;\n"
        "    float along=clamp(dot(p,stringEnd)/max(dot(stringEnd,stringEnd),.000001),0.0,1.0); float stringMask=1.0-smoothstep(pixel*.55,pixel*1.6,length(p-stringEnd*along));\n"
        "    color=mix(color,float3(0.38),stringMask*0.55); alpha=mix(alpha,1.0,stringMask*0.55);\n"
        "    float rr=dot(q,q)/(radius*radius);\n"
        "    if (rr < 1.0) {\n"
        "    float2 nxy=q/radius; float z=sqrt(max(0.0,1.0-rr));\n"
        "    const float longitudeCells=56.0;\n"
        "    const float longitudeDensity=longitudeCells/(2.0*3.14159265359);\n"
        "    float lon=atan2(nxy.x,z)+rotation; float lat=asin(nxy.y);\n"
        "    float2 grid=float2(lon*longitudeDensity,lat*10.0); float2 cell=floor(grid); float2 edge=abs(fract(grid)-0.5);\n"
        "    float wrappedCell=fmod(fmod(cell.x,longitudeCells)+longitudeCells,longitudeCells);\n"
        "    float seam=smoothstep(0.43,0.49,max(edge.x,edge.y)); float facet=hash21(float2(wrappedCell,cell.y));\n"
        "    float flon=(cell.x+0.5)/longitudeDensity-rotation; float flat=(cell.y+0.5)/10.0;\n"
        "    float3 fn=normalize(float3(sin(flon)*cos(flat),sin(flat),cos(flon)*cos(flat)));\n"
        "    float3 key=normalize(float3(-0.6,-0.7,1.0)); float3 fill=normalize(float3(0.85,0.15,0.6));\n"
        "    float diffuse=0.15+0.38*max(0.0,dot(fn,key));\n"
        "    float spec=pow(max(0.0,dot(fn,key)),72.0)*1.8+pow(max(0.0,dot(fn,fill)),110.0);\n"
        "    float reflection=pow(0.5+0.5*sin(flon*7.0+flat*4.0+facet*2.0),5.0);\n"
        "    float rim=pow(1.0-z,2.2); float silver=diffuse+reflection*0.32+spec+rim*0.25;\n"
        "    float3 ball=float3(clamp(silver,0.0,1.0))*(1.0-seam*0.65);\n"
        "    float coverage=1.0-smoothstep(radius-pixel,radius,length(q));\n"
        "      color=mix(color,ball,coverage); alpha=mix(alpha,1.0,coverage);\n"
        "    }\n"
        "  }\n"
        "  return float4(color,alpha);\n"
        "}\n";
}

- (instancetype)init {
    if ((self = [super init])) {
        self.windows = [NSMutableArray new];
        self.renderers = [NSMutableArray new];
        _animation = [DiscoAnimation new];
        _nowPlaying = [DiscoNowPlaying new];
        __weak DiscoAnimation *weakAnimation = _animation;
        _nowPlaying.paletteChanged = ^(NSArray<NSColor *> *colors) { [weakAnimation setAlbumColors:colors]; };
        _device = MTLCreateSystemDefaultDevice();
        if (_device) {
            NSError *error = nil;
            id<MTLLibrary> library = [_device newLibraryWithSource:DiscoShaderSource() options:nil error:&error];
            if (library) {
                MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
                descriptor.vertexFunction = [library newFunctionWithName:@"discoVertex"];
                descriptor.fragmentFunction = [library newFunctionWithName:@"discoFragment"];
                descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                descriptor.colorAttachments[0].blendingEnabled = YES;
                descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
                descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
                _pipeline = [_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
                _commandQueue = [_device newCommandQueue];
            }
            if (!_pipeline) NSLog(@"Could not prepare disco shader: %@", error.localizedDescription);
        }
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screensChanged:)
            name:NSApplicationDidChangeScreenParametersNotification object:nil];
    }
    return self;
}

- (void)rebuildOverlays {
    for (NSWindow *window in self.windows) {
        if ([window.contentView isKindOfClass:DiscoBallView.class]) [(DiscoBallView *)window.contentView cancelPull];
        [window orderOut:nil];
    }
    [self.windows removeAllObjects];
    [self.renderers removeAllObjects];
    if (!_pipeline || !_commandQueue) return;
    for (NSScreen *screen in NSScreen.screens) {
        for (NSUInteger pass = 0; pass < 2; pass++) {
            BOOL ballPass = pass == 1;
            NSRect frame = screen.frame;
            if (ballPass) {
                CGFloat height = fmin(NSHeight(frame), fmax(180.0, NSHeight(frame) * 0.18));
                CGFloat width = fmax(160.0, NSHeight(frame) * 0.16);
                frame = NSMakeRect(NSMidX(screen.frame) - width * 0.5,
                    NSMaxY(screen.frame) - height, width, height);
            }
            DiscoPanel *panel = [[DiscoPanel alloc] initWithContentRect:frame
                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                backing:NSBackingStoreBuffered defer:NO screen:screen];
            panel.opaque = NO;
            panel.backgroundColor = NSColor.clearColor;
            panel.hasShadow = NO;
            panel.ignoresMouseEvents = !ballPass;
            panel.level = CGWindowLevelForKey(kCGScreenSaverWindowLevelKey) - 1;
            panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary |
                NSWindowCollectionBehaviorIgnoresCycle;
            NSRect viewFrame = NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame));
            MTKView *view = ballPass
                ? [[DiscoBallView alloc] initWithFrame:viewFrame device:_device]
                : [[MTKView alloc] initWithFrame:viewFrame device:_device];
            view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
            view.clearColor = MTLClearColorMake(0, 0, 0, 0);
            view.preferredFramesPerSecond = 60;
            view.autoResizeDrawable = NO;
            CGFloat scale = ballPass ? screen.backingScaleFactor : 1.0;
            view.drawableSize = NSMakeSize(NSWidth(frame) * scale, NSHeight(frame) * scale);
            view.paused = YES;
            view.enableSetNeedsDisplay = NO;
            view.layer.opaque = NO;
            DiscoRenderer *renderer = [[DiscoRenderer alloc] initWithPipeline:_pipeline
                commandQueue:_commandQueue animation:_animation screen:screen ballPass:ballPass];
            view.delegate = renderer;
            if (ballPass) {
                ((DiscoBallView *)view).animation = _animation;
                ((DiscoBallView *)view).discoScreen = screen;
                __weak DiscoOverlayController *weakSelf = self;
                ((DiscoBallView *)view).cancelHandler = ^{ [weakSelf cancel]; };
            }
            panel.contentView = view;
            [self.windows addObject:panel];
            [self.renderers addObject:renderer];
        }
    }
}

- (void)show {
    if (_visible || !_pipeline) return;
    _visible = YES;
    _transitionGeneration++;
    if (!self.windows.count) [self rebuildOverlays];
    double remaining = [_animation setActive:YES];
    double dimmingDelay = fmax(0, DiscoDimmingDuration-(DiscoDuration-remaining));
    if (self.activeChanged) self.activeChanged(YES);
    if (!_escapeMonitor) {
        __weak DiscoOverlayController *weakSelf = self;
        _escapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
            handler:^NSEvent *(NSEvent *event) {
                if (event.keyCode != 53) return event;
                [weakSelf cancel];
                return nil;
            }];
    }
    for (DiscoPanel *panel in self.windows) {
        MTKView *view = (MTKView *)panel.contentView;
        view.paused = NO;
        panel.alphaValue = 1;
        [view draw];
        [panel orderFrontRegardless];
    }
    NSUInteger generation = _transitionGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dimmingDelay*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_visible && generation == self->_transitionGeneration) [self->_nowPlaying show];
    });
}

- (void)hide {
    if (!_visible) return;
    _visible = NO;
    if (self.activeChanged) self.activeChanged(NO);
    [_nowPlaying hide];
    for (NSWindow *window in self.windows)
        if ([window.contentView isKindOfClass:DiscoBallView.class]) [(DiscoBallView *)window.contentView cancelPull];
    if (_escapeMonitor) {
        [NSEvent removeMonitor:_escapeMonitor];
        _escapeMonitor = nil;
    }
    NSUInteger generation = ++_transitionGeneration;
    double remaining = [_animation setActive:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((remaining + 1.0 / 60.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_visible || generation != self->_transitionGeneration) return;
        for (DiscoPanel *panel in self.windows) {
            [(MTKView *)panel.contentView setPaused:YES];
            [panel orderOut:nil];
        }
    });
}

- (void)cancel {
    [self hide];
    if (self.cancelHandler) self.cancelHandler();
}

- (void)screensChanged:(NSNotification *)notification {
    BOOL wasVisible = _visible;
    [_nowPlaying hide];
    _transitionGeneration++;
    [self rebuildOverlays];
    _visible = NO;
    if (wasVisible) [self show];
    else [_animation setActive:NO];
}

- (void)dealloc {
    if (_escapeMonitor) [NSEvent removeMonitor:_escapeMonitor];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    for (NSWindow *window in self.windows) {
        if ([window.contentView isKindOfClass:DiscoBallView.class]) [(DiscoBallView *)window.contentView cancelPull];
        [window orderOut:nil];
    }
}
@end
