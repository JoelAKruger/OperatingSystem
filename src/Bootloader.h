// Joel Kruger
// 09/01/2025
// https://github.com/JoelAKruger/

#include <stdint.h>

typedef uint8_t  u8;
typedef int8_t   i8;
typedef uint16_t u16;
typedef int16_t  i16;
typedef uint32_t u32;
typedef int32_t  i32;
typedef uint64_t u64;
typedef int64_t  i64;

typedef float  f32;
typedef double f64;

typedef unsigned long long  UINT64;
typedef unsigned int        UINT32;
typedef unsigned short      CHAR16;
typedef unsigned short      UINT16;
typedef unsigned char       UINT8;
typedef UINT64 UINTN;

typedef struct {} *EFI_HANDLE;
typedef struct SIMPLE_INPUT_INTERFACE SIMPLE_INPUT_INTERFACE;
typedef struct SIMPLE_TEXT_OUTPUT_INTERFACE SIMPLE_TEXT_OUTPUT_INTERFACE;
typedef struct EFI_RUNTIME_SERVICES EFI_RUNTIME_SERVICES;
typedef struct EFI_BOOT_SERVICES EFI_BOOT_SERVICES;
typedef struct EFI_CONFIGURATION_TABLE EFI_CONFIGURATION_TABLE;
typedef struct EFI_GRAPHICS_OUTPUT_PROTOCOL EFI_GRAPHICS_OUTPUT_PROTOCOL;

typedef struct {
   UINT32    Data1;
   UINT16    Data2;
   UINT16    Data3;
   UINT8     Data4[8];
 } GUID;

typedef GUID EFI_GUID;

typedef struct _EFI_TABLE_HEADER {
    UINT64                      Signature;
    UINT32                      Revision;
    UINT32                      HeaderSize;
    UINT32                      CRC32;
    UINT32                      Reserved;
} EFI_TABLE_HEADER;

typedef struct _EFI_SYSTEM_TABLE {
    EFI_TABLE_HEADER                Hdr;

    CHAR16                          *FirmwareVendor;
    UINT32                          FirmwareRevision;

    EFI_HANDLE                      ConsoleInHandle;
    SIMPLE_INPUT_INTERFACE          *ConIn;

    EFI_HANDLE                      ConsoleOutHandle;
    SIMPLE_TEXT_OUTPUT_INTERFACE    *ConOut;

    EFI_HANDLE                      StandardErrorHandle;
    SIMPLE_TEXT_OUTPUT_INTERFACE    *StdErr;

    EFI_RUNTIME_SERVICES            *RuntimeServices;
    EFI_BOOT_SERVICES               *BootServices;

    UINTN                           NumberOfTableEntries;
    EFI_CONFIGURATION_TABLE         *ConfigurationTable;

} EFI_SYSTEM_TABLE;

#define EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID \
   { \
     0x9042a9de, 0x23dc, 0x4a38, {0x96, 0xfb, 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a } \
   }

typedef UINTN RETURN_STATUS;
typedef RETURN_STATUS EFI_STATUS;