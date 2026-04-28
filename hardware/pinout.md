# Pinout — Nucleo-H563ZI

> Draft. Validate against the Nucleo-H563ZI User Manual (UM3115) before
> wiring. Do not trust this table without checking.

## Vehicle through-lamp outputs (12 GPIO)

| Approach | Lamp   | MCU pin | Nucleo pin (CN10/CN11) |
|----------|--------|---------|------------------------|
| North    | Red    | PD0     | TBD                    |
| North    | Yellow | PD1     | TBD                    |
| North    | Green  | PD2     | TBD                    |
| South    | Red    | PD3     | TBD                    |
| South    | Yellow | PD4     | TBD                    |
| South    | Green  | PD5     | TBD                    |
| East     | Red    | PD6     | TBD                    |
| East     | Yellow | PD7     | TBD                    |
| East     | Green  | PD8     | TBD                    |
| West     | Red    | PD9     | TBD                    |
| West     | Yellow | PD10    | TBD                    |
| West     | Green  | PD11    | TBD                    |

## Left-turn arrow outputs (12 GPIO)

(To be assigned. Suggest PE0..PE11.)

## Pedestrian indicators (8 GPIO)

(To be assigned. Suggest PF0..PF7.)

## Pedestrian buttons (4 GPIO, input pull-up)

| Crosswalk | MCU pin |
|-----------|---------|
| NS_North  | PG0     |
| NS_South  | PG1     |
| EW_East   | PG2     |
| EW_West   | PG3     |

## Diagnostic UART

| Function | MCU pin | Notes                                  |
|----------|---------|----------------------------------------|
| TX       | PD8     | USART3 TX, ST-LINK virtual COM port    |
| RX       | PD9     | USART3 RX                              |

> Note: PD8/PD9 conflict with the through-lamp assignments above. Resolve
> before fabricating a shield. The ST-LINK VCP pins are documented in
> UM3115 §6.9.

## External MMU interface

| Function           | MCU pin | Notes                       |
|--------------------|---------|-----------------------------|
| MMU heartbeat OUT  | PB0     | 1 Hz square wave, FR-SF-06  |
| MMU fault IN       | PB1     | Active high; FR-SF-07       |

## Reset

| Function     | MCU pin | Notes                  |
|--------------|---------|------------------------|
| Manual reset | PB2     | Input pull-up; FR-UI-02|
