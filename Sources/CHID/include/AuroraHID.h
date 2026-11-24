#ifndef AIROX_AURORA_HID_H
#define AIROX_AURORA_HID_H

#include <stdbool.h>
#include <stdint.h>

typedef struct AuroraHID AuroraHID;

typedef enum {
    AuroraHIDCable = 0xfb09,
    AuroraHIDReceiver = 0xfb08,
} AuroraHIDRoute;

bool aurora_hid_present(AuroraHIDRoute route);
AuroraHID *aurora_hid_open(AuroraHIDRoute route, int32_t *status);
bool aurora_hid_is_pairable_receiver(AuroraHID *hid);
bool aurora_hid_is_aurora_product(AuroraHID *hid);
int32_t aurora_hid_read(AuroraHID *hid, uint16_t address, uint8_t count, uint8_t *output);
int32_t aurora_hid_write(AuroraHID *hid, uint16_t address, uint8_t count, const uint8_t *data);
int32_t aurora_hid_command(AuroraHID *hid, uint8_t command, uint8_t argument_count,
                           const uint8_t *arguments, uint32_t timeout_ms, uint8_t *reply);
void aurora_hid_close(AuroraHID *hid);

#endif
