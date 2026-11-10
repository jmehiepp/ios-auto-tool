#include "../engine/touch/gesture.h"
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <time.h>
static bool script_thread,stopped;
static int down_count,up_count;
bool script_is_current_thread(void) { return script_thread; }
bool script_should_stop(void) { return stopped; }
void send_touch_down(double x,double y,uint32_t finger) { (void)x;(void)y;(void)finger;down_count++; }
void send_touch_move(double x,double y,uint32_t finger) { (void)x;(void)y;(void)finger; }
void send_touch_up(double x,double y,uint32_t finger) { (void)x;(void)y;(void)finger;up_count++; }
static double milliseconds(void) { struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1000.0+t.tv_nsec/1000000.0; }
int main(void) {
    stopped=true;script_thread=true;double start=milliseconds();c_long_press(1,2,30000);
    assert(milliseconds()-start<1000 && down_count==1 && up_count==1);
    script_thread=false;start=milliseconds();c_swipe(1,2,3,4,80);
    assert(milliseconds()-start>=50 && down_count==2 && up_count==2);
    puts("Gesture cancellation and manual control isolation tests passed");return 0;
}
