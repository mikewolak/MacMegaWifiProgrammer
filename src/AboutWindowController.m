//  AboutWindowController.m

#import "AboutWindowController.h"
#import <SceneKit/SceneKit.h>

@implementation AboutWindowController

+ (instancetype)sharedController
{
    static AboutWindowController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AboutWindowController alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    NSRect frame = NSMakeRect(0, 0, 380, 460);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskMiniaturizable;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"About MegaWifi Programmer";
    win.releasedWhenClosed = NO;

    self = [super initWithWindow:win];
    if (!self) return nil;

    [self buildUI];
    [win center];
    return self;
}

- (void)buildUI
{
    NSView *content = self.window.contentView;

    // ── SceneKit view ────────────────────────────────────────────────────────
    SCNView *scnView = [[SCNView alloc] initWithFrame:NSZeroRect];
    scnView.translatesAutoresizingMaskIntoConstraints = NO;
    scnView.backgroundColor = [NSColor colorWithWhite:0.08 alpha:1.0];
    scnView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    scnView.allowsCameraControl = NO;
    [content addSubview:scnView];

    // ── Title label ──────────────────────────────────────────────────────────
    NSTextField *title = [NSTextField labelWithString:@"MegaWifi Programmer"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont boldSystemFontOfSize:20];
    title.textColor = [NSColor labelColor];
    title.alignment = NSTextAlignmentCenter;
    [content addSubview:title];

    // ── Version label ────────────────────────────────────────────────────────
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]
                    ?: @"1.0";
    NSTextField *version = [NSTextField labelWithString:[NSString stringWithFormat:@"Version %@", ver]];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.font = [NSFont systemFontOfSize:13];
    version.textColor = [NSColor secondaryLabelColor];
    version.alignment = NSTextAlignmentCenter;
    [content addSubview:version];

    // ── Date label ───────────────────────────────────────────────────────────
    NSTextField *dateLabel = [NSTextField labelWithString:@"March 15, 2026"];
    dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    dateLabel.font = [NSFont systemFontOfSize:12];
    dateLabel.textColor = [NSColor tertiaryLabelColor];
    dateLabel.alignment = NSTextAlignmentCenter;
    [content addSubview:dateLabel];

    // ── Layout ───────────────────────────────────────────────────────────────
    [NSLayoutConstraint activateConstraints:@[
        [scnView.topAnchor constraintEqualToAnchor:content.topAnchor],
        [scnView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scnView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scnView.heightAnchor constraintEqualToConstant:340],

        [title.topAnchor constraintEqualToAnchor:scnView.bottomAnchor constant:18],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [version.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [version.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [version.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [dateLabel.topAnchor constraintEqualToAnchor:version.bottomAnchor constant:4],
        [dateLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [dateLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
    ]];

    // ── Scene ────────────────────────────────────────────────────────────────
    SCNScene *scene = [SCNScene scene];
    scnView.scene = scene;

    // Camera
    SCNNode *cameraNode = [SCNNode node];
    cameraNode.camera = [SCNCamera camera];
    cameraNode.position = SCNVector3Make(0, 0, 4.5);
    [scene.rootNode addChildNode:cameraNode];

    // Ambient light
    SCNNode *ambient = [SCNNode node];
    ambient.light = [SCNLight light];
    ambient.light.type = SCNLightTypeAmbient;
    ambient.light.color = [NSColor colorWithWhite:0.35 alpha:1.0];
    [scene.rootNode addChildNode:ambient];

    // Omni light
    SCNNode *omni = [SCNNode node];
    omni.light = [SCNLight light];
    omni.light.type = SCNLightTypeOmni;
    omni.light.color = [NSColor whiteColor];
    omni.position = SCNVector3Make(5, 5, 8);
    [scene.rootNode addChildNode:omni];

    // Cube geometry
    SCNBox *box = [SCNBox boxWithWidth:2.0 height:2.0 length:2.0 chamferRadius:0.08];

    // Texture — same image on all 6 faces
    NSString *imgPath = [[NSBundle mainBundle] pathForResource:@"me_floyd" ofType:@"png"];
    NSImage *img = imgPath ? [[NSImage alloc] initWithContentsOfFile:imgPath] : nil;

    SCNMaterial *mat = [SCNMaterial material];
    mat.diffuse.contents = img ?: [NSColor systemPurpleColor];
    mat.diffuse.wrapS = SCNWrapModeRepeat;
    mat.diffuse.wrapT = SCNWrapModeRepeat;
    mat.specular.contents = [NSColor colorWithWhite:0.5 alpha:1.0];
    mat.shininess = 0.5;
    box.materials = @[mat, mat, mat, mat, mat, mat];

    SCNNode *cubeNode = [SCNNode nodeWithGeometry:box];
    [scene.rootNode addChildNode:cubeNode];

    // Rotation animation
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"rotation"];
    spin.fromValue = [NSValue valueWithSCNVector4:SCNVector4Make(1, 0.4, 0.2, 0)];
    spin.toValue   = [NSValue valueWithSCNVector4:SCNVector4Make(1, 0.4, 0.2, M_PI * 2)];
    spin.duration  = 6.0;
    spin.repeatCount = HUGE_VALF;
    [cubeNode addAnimation:spin forKey:@"spin"];

    scnView.playing = YES;
}

@end
