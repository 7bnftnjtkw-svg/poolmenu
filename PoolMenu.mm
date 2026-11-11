// 8 Ball Pool Menu — Humanized Aim + Coins Toggle
// Coins use placeholder offset. Dump real value or it does nothing.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <dlfcn.h>

static BOOL g_menuVisible = NO;
static BOOL g_aimbotEnabled = YES;
static BOOL g_espEnabled = YES;
static BOOL g_coinsEnabled = NO;
static float g_aimStrength = 0.58f;
static float g_espDistance = 36.0f;

#define OFF_CUE_ANGLE        0x1A2B3C
#define OFF_BALL_ARRAY       0x4D5E6F
#define OFF_COINS            0xABCDEF   // REPLACE WITH REAL OFFSET
#define BALL_STRIDE          0x48
#define BALL_POS_X           0x10
#define BALL_POS_Y           0x14
#define BALL_IS_POCKETED     0x28
#define BALL_TYPE            0x2C

typedef struct { float x, y; } Vec2;

static float Distance(Vec2 a, Vec2 b) {
    float dx = a.x - b.x, dy = a.y - b.y;
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

static uintptr_t GetImageBase(const char *name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *img = _dyld_get_image_name(i);
        if (img && strstr(img, name))
            return (uintptr_t)_dyld_get_image_header(i);
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

static Vec2 GetCueBall() { return GetBall(0).pos; }
static float GetCurrentAngle() { return Read<float>(g_base + OFF_CUE_ANGLE); }

static void SetCueAngle(float angle) {
    Write(g_base + OFF_CUE_ANGLE, &angle, sizeof(float));
}

static float FindBestAngle(Vec2 cue) {
    float bestScore = -1.0f, bestAngle = 0.0f;
    for (int i = 1; i < 16; i++) {
        Ball b = GetBall(i);
        if (!b.valid) continue;
        float dist = Distance(cue, b.pos);
        if (dist < 0.7f || dist > g_espDistance) continue;
        float score = 1.0f / (dist + 0.15f);
        if (score > bestScore) {
            bestScore = score;
            bestAngle = AngleTo(cue, b.pos);
        }
    }
    return bestAngle;
}

static void RunAimbot() {
    if (!g_aimbotEnabled) return;
    if ((arc4random() % 100) < 10) return;

    Vec2 cue = GetCueBall();
    float target = FindBestAngle(cue);
    float current = GetCurrentAngle();
    float delta = NormalizeAngle(target - current);
    float jitter = ((arc4random() % 160) - 80) / 1800.0f;
    float strength = g_aimStrength + jitter;
    if (strength > 0.72f) strength = 0.72f;
    if (strength < 0.38f) strength = 0.38f;

    float newAngle = current + delta * strength;
    SetCueAngle(newAngle);
}

static void ApplyCoins() {
    if (!g_coinsEnabled || OFF_COINS == 0xABCDEF) return;
    int coins = 500000;
    Write(g_base + OFF_COINS, &coins, sizeof(int));
}

@interface ESPView : UIView
@end
@implementation ESPView
- (void)drawRect:(CGRect)rect {
    if (!g_espEnabled) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    Vec2 cue = GetCueBall();
    float scaleX = self.bounds.size.width / 200.0f;
    float scaleY = self.bounds.size.height / 100.0f;
    float offsetX = 20.0f, offsetY = 80.0f;
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
        CGContextSetLineWidth(ctx, 1.6);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(sx - 7, sy - 7, 14, 14));
        if (i > 0 && Distance(cue, b.pos) < 30.0f) {
            CGContextMoveToPoint(ctx, offsetX + cue.x * scaleX, offsetY + cue.y * scaleY);
            CGContextAddLineToPoint(ctx, sx, sy);
            CGContextStrokePath(ctx);
        }
    }
}
@end

@interface ModMenuView : UIView
@property (nonatomic, strong) UISwitch *aimSwitch;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UISwitch *coinsSwitch;
@property (nonatomic, strong) UISlider *strengthSlider;
@end

@implementation ModMenuView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1].CGColor;
        self.clipsToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 200, 22)];
        title.text = @"Pool Menu";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:title];

        UILabel *aimL = [[UILabel alloc] initWithFrame:CGRectMake(16, 46, 130, 20)];
        aimL.text = @"Aim Assist";
        aimL.textColor = [UIColor lightGrayColor];
        aimL.font = [UIFont systemFontOfSize:14];
        [self addSubview:aimL];
        self.aimSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(190, 42, 51, 31)];
        self.aimSwitch.on = g_aimbotEnabled;
        [self.aimSwitch addTarget:self action:@selector(toggleAim:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.aimSwitch];

        UILabel *espL = [[UILabel alloc] initWithFrame:CGRectMake(16, 86, 130, 20)];
        espL.text = @"ESP";
        espL.textColor = [UIColor lightGrayColor];
        espL.font = [UIFont systemFontOfSize:14];
        [self addSubview:espL];
        self.espSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(190, 82, 51, 31)];
        self.espSwitch.on = g_espEnabled;
        [self.espSwitch addTarget:self action:@selector(toggleESP:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.espSwitch];

        UILabel *coinsL = [[UILabel alloc] initWithFrame:CGRectMake(16, 126, 130, 20)];
        coinsL.text = @"Coins";
        coinsL.textColor = [UIColor lightGrayColor];
        coinsL.font = [UIFont systemFontOfSize:14];
        [self addSubview:coinsL];
        self.coinsSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(190, 122, 51, 31)];
        self.coinsSwitch.on = g_coinsEnabled;
        [self.coinsSwitch addTarget:self action:@selector(toggleCoins:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.coinsSwitch];

        UILabel *strL = [[UILabel alloc] initWithFrame:CGRectMake(16, 166, 130, 20)];
        strL.text = @"Strength";
        strL.textColor = [UIColor lightGrayColor];
        strL.font = [UIFont systemFontOfSize:14];
        [self addSubview:strL];
        self.strengthSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, 190, 220, 28)];
        self.strengthSlider.minimumValue = 0.3f;
        self.strengthSlider.maximumValue = 0.75f;
        self.strengthSlider.value = g_aimStrength;
        [self.strengthSlider addTarget:self action:@selector(strengthChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.strengthSlider];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(16, 230, 220, 34);
        [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];
    }
    return self;
}
- (void)toggleAim:(UISwitch *)s { g_aimbotEnabled = s.on; }
- (void)toggleESP:(UISwitch *)s { g_espEnabled = s.on; }
- (void)toggleCoins:(UISwitch *)s { g_coinsEnabled = s.on; }
- (void)strengthChanged:(UISlider *)s { g_aimStrength = s.value; }
- (void)closeMenu { g_menuVisible = NO; self.hidden = YES; }
@end

static ESPView *g_espView = nil;
static ModMenuView *g_menu = nil;
static UIWindow *g_keyWindow = nil;

static void ShowMenu() {
    if (!g_menu) {
        g_menu = [[ModMenuView alloc] initWithFrame:CGRectMake(40, 100, 250, 280)];
        [g_keyWindow addSubview:g_menu];
    }
    g_menu.hidden = NO;
    g_menuVisible = YES;
}

static void ToggleMenu() {
    g_menuVisible ? (g_menu.hidden = YES, g_menuVisible = NO) : ShowMenu();
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
        fab.frame = CGRectMake(g_keyWindow.bounds.size.width - 58, 90, 42, 42);
        fab.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.8];
        fab.layer.cornerRadius = 21;
        [fab setTitle:@"P" forState:UIControlStateNormal];
        [fab setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [g_keyWindow addSubview:fab];

        [NSTimer scheduledTimerWithTimeInterval:1.0/45.0 repeats:YES block:^(NSTimer *t) {
            if (g_aimbotEnabled) RunAimbot();
            if (g_coinsEnabled) ApplyCoins();
            [g_espView setNeedsDisplay];
        }];
    });
}

__attribute__((constructor))
static void Init() {
    g_base = GetImageBase("BallPool");
    if (!g_base) g_base = GetImageBase("UnityFramework");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ SetupUI(); });
}
