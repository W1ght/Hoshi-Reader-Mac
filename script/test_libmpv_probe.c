#include <mpv/client.h>
#include <stdio.h>

int main(int argc, char **argv) {
    mpv_handle *handle = mpv_create();
    if (!handle) {
        fputs("failed to create libmpv handle\n", stderr);
        return 1;
    }
    mpv_set_option_string(handle, "config", "no");
    mpv_set_option_string(handle, "vo", "null");
    mpv_set_option_string(handle, "ao", "null");
    int status = mpv_initialize(handle);
    if (status < 0) {
        fprintf(stderr, "failed to initialize libmpv: %s\n", mpv_error_string(status));
        mpv_destroy(handle);
        return 1;
    }

    if (argc > 1) {
        const char *command[] = {"loadfile", argv[1], "replace", NULL};
        status = mpv_command(handle, command);
        if (status < 0) {
            fprintf(stderr, "libmpv load command failed: %s\n", mpv_error_string(status));
            mpv_terminate_destroy(handle);
            return 1;
        }
        for (;;) {
            mpv_event *event = mpv_wait_event(handle, 5);
            if (event->event_id == MPV_EVENT_FILE_LOADED) {
                double duration = 0;
                status = mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration);
                if (status < 0 || duration <= 0) {
                    fputs("libmpv duration probe failed\n", stderr);
                    mpv_terminate_destroy(handle);
                    return 1;
                }
                printf("libmpv media probe passed (%.3fs)\n", duration);
                break;
            }
            if (event->event_id == MPV_EVENT_END_FILE) {
                mpv_event_end_file *end = event->data;
                if (end && end->error < 0) {
                    fprintf(stderr, "libmpv media probe failed: %s\n", mpv_error_string(end->error));
                    mpv_terminate_destroy(handle);
                    return 1;
                }
            }
            if (event->event_id == MPV_EVENT_NONE) {
                fputs("libmpv media probe timed out\n", stderr);
                mpv_terminate_destroy(handle);
                return 1;
            }
        }
    }

    mpv_terminate_destroy(handle);
    puts("libmpv probe passed");
    return 0;
}
