#ifndef AIROX_CHID_H
#define AIROX_CHID_H

#include <stdbool.h>
#include <stdint.h>
#include "AuroraHID.h"
#include "MouseDiscovery.h"

typedef struct AiroxHID AiroxHID;

enum {
    AiroxHIDNotFound = -1,
    AiroxHIDAmbiguous = -2,
    AiroxHIDNoReply = -3,
    AiroxHIDUnavailable = -4,
};

bool airox_hid_present(void);
AiroxHID *airox_hid_open(int32_t *status);
int32_t airox_hid_query(AiroxHID *hid, uint8_t code, uint8_t *response);
int32_t airox_hid_write(AiroxHID *hid, const uint8_t *packet);
int32_t airox_hid_write_confirmed(AiroxHID *hid, const uint8_t *packet);
void airox_hid_close(AiroxHID *hid);

#endif
