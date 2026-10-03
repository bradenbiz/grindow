#include "CStrafe.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

// Compiled with CGEventPost redirected to this observer. No events reach macOS.
static unsigned int posts;
static double expectedVelocity;
static CGPoint expectedLocation;
void grindow_test_event_post(CGEventTapLocation tap, CGEventRef event) {
    assert(tap == kCGSessionEventTap);
    CGPoint point = CGEventGetLocation(event);
    assert(point.x == expectedLocation.x && point.y == expectedLocation.y);
    if (strafe_event_cgs_type(event) == strafe_cgs_event_gesture()) { return; }
    assert(strafe_event_cgs_type(event) == strafe_cgs_event_dock_control());
    const int64_t phases[] = {1, 2, 4};
    int64_t phase = strafe_event_gesture_phase(event);
    assert(phase == phases[posts % 3]);
    double velocity = expectedVelocity;
    if (strafe_uses_iohid_payload()) { velocity = phase == 4 ? -velocity : 0; }
    assert(fabs(strafe_event_swipe_velocity_x(event) - velocity) < 0.1);
    posts++;
}

int main(void) {
    expectedLocation = CGPointMake(-800, 450);
    expectedVelocity = -4000;
    assert(strafe_post_switch_gestures(StrafeDirectionLeft, 2, expectedLocation));
    assert(posts == 6); // Two complete gestures posted before the call returns.
    posts = 0;
    expectedVelocity = 2000;
    assert(strafe_post_switch_gestures(StrafeDirectionRight, 1, expectedLocation));
    assert(posts == 3);
    posts = 0;
    assert(!strafe_post_switch_gestures(StrafeDirectionRight, 0, expectedLocation));
    assert(!strafe_post_switch_gestures(StrafeDirectionRight, 129, expectedLocation));
    assert(posts == 0);
    expectedVelocity = 30000;
    assert(strafe_post_switch_gestures(StrafeDirectionRight, 16, expectedLocation));
    assert(posts == 48);
    puts("Native burst tests passed (CGEventPost mocked; no live switching).");
}
