// iOS 8 Ball Pool External-Style Mod Menu
// Language: Objective-C++ | Runtime: iOS 15–18 (jailbroken or TrollStore)
// Inject via Substrate / ElleKit / TrollStore IPA mod
// Offsets are placeholders — dump the current binary and update

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <dlfcn.h>

// ============ CONFIG ============
static BOOL g_menuVisible = NO;
static BOOL g_aimbotEnabled = YES;
static BOOL g_espEnabled = YES;
static BOOL g_autoAim = NO;
static float g_aimStrength = 0.85f;
static float g_espDistance = 40.0f;

// ============ OFFSETS (update per app version) ============
#define OFF_CUE_ANGLE        0x1A2B3C
#define OFF_BALL_ARRAY       0x4D5E6F
#define OFF_TABLE_BOUNDS     0x7A8B9C
#define OFF_PLAYER_TURN      0x0F1E2D
#define BALL_STRIDE          0x48
#define BALL_POS_X           0x10
#define BALL_POS_Y           0x14
#define BALL_IS_POCKETED     0x28
#define BALL_TYPE            0x2C

// ============ MATH ============
typedef struct { float x, y; } Vec2;

static float Distance(Vec2 a, Vec2 b) {
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    return sqrtf(dx*dx + dy*dy);
}

static float AngleTo(Vec2 from, Vec2 to) {
    return atan2f(to.y - from.y, to.x - from.x);
}

static float NormalizeAngle(float a) {
    while (a > M_PI) a -= 2.0f * M_PI;
    while (a < -M_PI) a += 2.0f * M_PI;
    return a;
}

// ============ MEMORY ============
static uintptr_t GetImageBase(const char *name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *img = _dyld_get_image_name(i);
        if (img && strstr(img, name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

template<typename T>
static T Read(uintptr_t addr) {
    T v{};
    vm_size_t sz = sizeof(T);
    vm_read_overwrite(mach_task_self(), (vm_address_t)addr, sz, (vm_address_t)&v, &sz);
    return v;
}

static void Write(uintptr_t addr, const void *data, size_t size) {
    vm_write(mach_task_self(), (vm_address_t)addr, (vm_offset_t)data, (mach_msg_type_number_t)size);
}

// ============ GAME STATE ============
typedef struct {
    Vec2 pos;
    int type;
    BOOL pocketed;
    BOOL valid;
} Ball;

static uintptr_t g_base = 0;

static Ball GetBall(int index) {
    Ball b = {};
    uintptr_t arr = Read<uintptr_t>(g_base + OFF_BALL_ARRAY);
    if (!arr) return b;
    uintptr_t ptr = arr + index * BALL_STRIDE;
    b.pos.x = Read<float>(ptr + BALL_POS_X);
    b.pos.y = Read<float>(ptr + BALL_POS_Y);
    b.type = Read<int>(ptr + BALL_TYPE);
    b.pocketed = Read<BOOL>(ptr + BALL_IS_POCKETED);
    b.valid = !b.pocketed;
    return b;
}

static Vec2 GetCueBall() {
    return GetBall(0).pos;
}

static float GetCurrentAngle() {
    return Read<float>(g_base + OFF_CUE_ANGLE);
}

static void SetCueAngle(float angle) {
    Write(g_base + OFF_CUE_ANGLE, &angle, sizeof(float));
}

// ============ AIMBOT ============
static float FindBestAngle(Vec2 cue, int targetType) {
    float bestScore = -1.0f;
    float bestAngle = 0.0f;

    for (int i = 1; i < 16; i++) {
        Ball b = GetBall(i);
        if (!b.valid) continue;

        if (targetType == 0 && (b.type < 1 || b.type > 7)) continue;
        if (targetType == 1 && (b.type < 9 || b.type > 15)) continue;
        if (targetType == 8 && b.type != 8) continue;

        float dist = Distance(cue, b.pos);
        if (dist < 0.5f || dist > g_espDistance) continue;

        float ang = AngleTo(cue, b.pos);
        float score = 1.0f / (dist + 0.1f);

        if (score > bestScore) {
            bestScore = score;
            bestAngle = ang;
        }
    }
    return bestAngle;
}

static void RunAimbot() {
    if (!g_aimbotEnabled) return;

    Vec2 cue = GetCueBall();
    float target = FindBestAngle(cue, -1);
    float current = GetCurrentAngle();

    float delta = NormalizeAngle(target - current);
    float newAngle = current + delta * g_aimStrength;

    SetCueAngle(newAngle);
}

// ============ ESP DRAW ============
@interface ESPView : UIView
@end

@implementation ESPView
- (void)drawRect:(CGRect)rect {
    if (!g_espEnabled) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    Vec2 cue = GetCueBall();

    float scaleX = self.bounds.size.width / 200.0f;
    float scaleY = self.bounds.size.height / 100.0f;
    float offsetX = 20.0f;
    float offsetY = 80.0f;

    for (int i = 0; i < 16; i++) {
        Ball b = GetBall(i);
        if (!b.valid) continue;

        float sx = offsetX + b.pos.x * scaleX;
        float sy = offsetY + b.pos.y * scaleY;

        UIColor *col = (i == 0) ? [UIColor whiteColor] :
                       (b.type == 8) ? [UIColor blackColor] :
                       (b.type <= 7) ? [UIColor systemYellowColor] :
                                       [UIColor systemBlueColor];

        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(sx - 8, sy - 8, 16, 16));

        if (i > 0) {
            float cx = offsetX + cue.x * scaleX;
            float cy = offsetY + cue.y * scaleY;
            CGContextMoveToPoint(ctx, cx, cy);
            CGContextAddLineToPoint(ctx, sx, sy);
            CGContextStrokePath(ctx);
        }
    }
}
@end

// ============ FLOATING MENU ============
@interface ModMenuView : UIView
@property (nonatomic, strong) UISwitch *aimSwitch;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UISlider *strengthSlider;
@property (nonatomic, strong) UIButton *closeBtn;
@end

@implementation ModMenuView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
        self.layer.cornerRadius = 14;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1].CGColor;
        self.clipsToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 200, 24)];
        title.text = @"Pool Menu";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:17];
        [self addSubview:title];

        UILabel *aimL = [[UILabel alloc] initWithFrame:CGRectMake(16, 50, 120, 22)];
        aimL.text = @"Aimbot";
        aimL.textColor = [UIColor lightGrayColor];
        aimL.font = [UIFont systemFontOfSize:15];
        [self addSubview:aimL];

        self.aimSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, 46, 51, 31)];
        self.aimSwitch.on = g_aimbotEnabled;
        [self.aimSwitch addTarget:self action:@selector(toggleAim:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.aimSwitch];

        UILabel *espL = [[UILabel alloc] initWithFrame:CGRectMake(16, 90, 120, 22)];
        espL.text = @"ESP Lines";
        espL.textColor = [UIColor lightGrayColor];
        espL.font = [UIFont systemFontOfSize:15];
        [self addSubview:espL];

        self.espSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, 86, 51, 31)];
        self.espSwitch.on = g_espEnabled;
        [self.espSwitch addTarget:self action:@selector(toggleESP:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.espSwitch];

        UILabel *strL = [[UILabel alloc] initWithFrame:CGRectMake(16, 130, 120, 22)];
        strL.text = @"Aim Strength";
        strL.textColor = [UIColor lightGrayColor];
        strL.font = [UIFont systemFontOfSize:15];
        [self addSubview:strL];

        self.strengthSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, 158, 230, 30)];
        self.strengthSlider.minimumValue = 0.1f;
        self.strengthSlider.maximumValue = 1.0f;
        self.strengthSlider.value = g_aimStrength;
        [self.strengthSlider addTarget:self action:@selector(strengthChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.strengthSlider];

        self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        self.closeBtn.frame = CGRectMake(16, 200, 230, 36);
        [self.closeBtn setTitle:@"Close" forState:UIControlStateNormal];
        [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        self.closeBtn.layer.cornerRadius = 8;
        [self.closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeBtn];
    }
    return self;
}

- (void)toggleAim:(UISwitch *)s { g_aimbotEnabled = s.on; }
- (void)toggleESP:(UISwitch *)s { g_espEnabled = s.on; }
- (void)strengthChanged:(UISlider *)s { g_aimStrength = s.value; }
- (void)closeMenu {
    g_menuVisible = NO;
    self.hidden = YES;
}
@end

// ============ ROOT CONTROLLER HOOK ============
static ESPView *g_espView = nil;
static ModMenuView *g_menu = nil;
static UIWindow *g_keyWindow = nil;

static void ShowMenu() {
    if (!g_menu) {
        g_menu = [[ModMenuView alloc] initWithFrame:CGRectMake(40, 120, 260, 250)];
        [g_keyWindow addSubview:g_menu];
    }
    g_menu.hidden = NO;
    g_menuVisible = YES;
}

static void ToggleMenu() {
    if (g_menuVisible) {
        g_menu.hidden = YES;
        g_menuVisible = NO;
    } else {
        ShowMenu();
    }
}

@interface FloatingButton : UIButton
@end
@implementation FloatingButton
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    ToggleMenu();
}
@end

static void SetupUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        g_keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!g_keyWindow) return;

        g_espView = [[ESPView alloc] initWithFrame:g_keyWindow.bounds];
        g_espView.userInteractionEnabled = NO;
        g_espView.backgroundColor = [UIColor clearColor];
        [g_keyWindow addSubview:g_espView];

        FloatingButton *fab = [FloatingButton buttonWithType:UIButtonTypeCustom];
        fab.frame = CGRectMake(g_keyWindow.bounds.size.width - 60, 100, 44, 44);
        fab.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.85];
        fab.layer.cornerRadius = 22;
        [fab setTitle:@"P" forState:UIControlStateNormal];
        [fab setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [g_keyWindow addSubview:fab];

        [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 repeats:YES block:^(NSTimer *t) {
            if (g_aimbotEnabled) RunAimbot();
            [g_espView setNeedsDisplay];
        }];
    });
}

// ============ ENTRY ============
__attribute__((constructor))
static void Init() {
    g_base = GetImageBase("BallPool");
    if (!g_base) g_base = GetImageBase("UnityFramework");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SetupUI();
    });
}
