// Joel Kruger
// 09/01/2025
// https://github.com/JoelAKruger/

#include <efi/efi.h>
#include <efi/efilib.h>
#include <elf/elf.h>

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

typedef struct
{
    u32 Width, Height;
    u32 PixelsPerScanline;
    u32* Pixels;
} screen_buffer;

typedef struct
{
    screen_buffer Screen;
    
    u8* MemoryMap;
    u64 MemoryMapSize;
    u64 MemoryMapDescriptorSize;

    void* RSDP;
    EFI_TIME Time;
} system_info;

//The compiler can generate code that calls these functions automatically
void* memset(void *Dest, int Val, u64 Length)
{
    unsigned char *Ptr = (unsigned char*) Dest;
    while (Length-- > 0)
    {
        *Ptr++ = Val;
    }
    return Dest;
}

void memcpy(void* Dest_, void* Src_, u64 Count) 
{ 
    u8* Dest = (u8*)Dest_; 
    u8* Src = (u8*)Src_; 
    for (u64 I = 0; I < Count; I++) 
    {
        Dest[I] = Src[I]; 
    }
} 

static screen_buffer
GetScreenBuffer(EFI_SYSTEM_TABLE* SystemTable)
{
    screen_buffer Result = {};
    
    EFI_GRAPHICS_OUTPUT_PROTOCOL* GraphicsProtocol = 0;
    EFI_GUID GUID = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    
    EFI_STATUS Status = SystemTable->BootServices->LocateProtocol(&GUID, 0, (void**)&GraphicsProtocol);
    
    if (Status == EFI_SUCCESS)
    {
        //This may be necessary to "circumvent some buggy UEFI firmware"
        //https://wiki.osdev.org/GOP
        
        EFI_GRAPHICS_OUTPUT_MODE_INFORMATION* Info;
        UINTN InfoSize = sizeof(Info);
        u32 CurrentModeIndex = GraphicsProtocol->Mode ? GraphicsProtocol->Mode->Mode : 0;
        Status = GraphicsProtocol->QueryMode(GraphicsProtocol, CurrentModeIndex, &InfoSize, &Info);
        if (Status == EFI_NOT_STARTED)
        {
            Status = GraphicsProtocol->SetMode(GraphicsProtocol, 0);
        }
        
        //Store mode information and buffer
        Result.Width  = GraphicsProtocol->Mode->Info->HorizontalResolution;
        Result.Height = GraphicsProtocol->Mode->Info->VerticalResolution;
        Result.PixelsPerScanline = GraphicsProtocol->Mode->Info->PixelsPerScanLine;
        Result.Pixels = (u32*)GraphicsProtocol->Mode->FrameBufferBase;
    }
    
    return Result;
}

EFI_FILE* LoadFile(CHAR16* Path, EFI_HANDLE Image, EFI_SYSTEM_TABLE* SystemTable)
{
    EFI_LOADED_IMAGE* LoadedImage = 0;
    EFI_GUID LoadedImageProtocolGUID = EFI_LOADED_IMAGE_PROTOCOL_GUID;
    
    SystemTable->BootServices->HandleProtocol(Image, &LoadedImageProtocolGUID, (void**) &LoadedImage);
    
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL* FileSystem = 0;
    EFI_GUID SimpleFileSystemGUID = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
    SystemTable->BootServices->HandleProtocol(LoadedImage->DeviceHandle, &SimpleFileSystemGUID, (void**) &FileSystem);
    
    EFI_FILE* RootDirectory = 0;
    FileSystem->OpenVolume(FileSystem, &RootDirectory);
    
    EFI_FILE* LoadedFile = 0;
    RootDirectory->Open(RootDirectory, &LoadedFile, Path, EFI_FILE_MODE_READ, EFI_FILE_READ_ONLY);
    
    return LoadedFile;
}

static void*
LoadKernel(EFI_FILE* File, EFI_SYSTEM_TABLE* SystemTable)
{
    //Get file size
    UINTN FileInfoSize = 0;
    
    EFI_GUID FileInfoGUID = EFI_FILE_INFO_ID;
    File->GetInfo(File, &FileInfoGUID, &FileInfoSize, 0);
    
    EFI_FILE_INFO* FileInfo;
    SystemTable->BootServices->AllocatePool(EfiLoaderData, FileInfoSize, (void**) &FileInfo);
    
    File->GetInfo(File, &FileInfoGUID, &FileInfoSize, FileInfo);
    
    //Read header
    Elf64_Ehdr Header;
    
    UINTN Bytes = sizeof(Header);
    File->Read(File, &Bytes, &Header);
    
    //Verify header
    u32 ElfMagicBytes = *(u32*)ELFMAG;
    
    if ((*(u32*)Header.e_ident != ElfMagicBytes) ||
        Header.e_ident[EI_CLASS] != ELFCLASS64 ||
        Header.e_ident[EI_DATA] != ELFDATA2LSB ||
        Header.e_type != ET_EXEC ||
        Header.e_machine != EM_X86_64 ||
        Header.e_version != EV_CURRENT)
    {
        SystemTable->ConOut->OutputString(SystemTable->ConOut, L"Invalid Kernel Format");
        
        return 0;
    }
    
    //Read program headers
    Bytes = Header.e_phnum * Header.e_phentsize;
    u8* ProgramHeaders = 0;
    SystemTable->BootServices->AllocatePool(EfiLoaderData, Bytes, (void**) &ProgramHeaders);
    
    File->SetPosition(File, Header.e_phoff);
    File->Read(File, &Bytes, ProgramHeaders);
    
    //Read code
    for (u8* At = ProgramHeaders;
         At < ProgramHeaders + Bytes;
         At += Header.e_phentsize)
    {
        Elf64_Phdr* ProgramHeader = (Elf64_Phdr*)At;
        
        switch (ProgramHeader->p_type)
        {
            case PT_LOAD:
            {
                u64 PageCount = (ProgramHeader->p_memsz + 0x1000 - 1) / 0x1000;
                
                EFI_PHYSICAL_ADDRESS Memory = (EFI_PHYSICAL_ADDRESS)ProgramHeader->p_paddr;
                SystemTable->BootServices->AllocatePages(AllocateAddress, EfiLoaderData, PageCount, &Memory);
                
                File->SetPosition(File, ProgramHeader->p_offset);
                File->Read(File, &ProgramHeader->p_filesz, (void*)Memory);
            } break;
        }
    }
    
    return (void*)Header.e_entry;
}

int
GuidsAreEqual(EFI_GUID* Guid1, EFI_GUID* Guid2)
{
    return (Guid1->Data1 == Guid2->Data1 &&
            Guid1->Data2 == Guid2->Data2 &&
            Guid1->Data3 == Guid2->Data3 &&
            Guid1->Data4[0] == Guid2->Data4[0] &&
            Guid1->Data4[1] == Guid2->Data4[1] &&
            Guid1->Data4[2] == Guid2->Data4[2] &&
            Guid1->Data4[3] == Guid2->Data4[3] &&
            Guid1->Data4[4] == Guid2->Data4[4] &&
            Guid1->Data4[5] == Guid2->Data4[5] &&
            Guid1->Data4[6] == Guid2->Data4[6] &&
            Guid1->Data4[7] == Guid2->Data4[7]);
}

EFI_STATUS
GetRSDP(EFI_SYSTEM_TABLE *SystemTable, void** RSDP) {
    EFI_CONFIGURATION_TABLE *ConfigTable;
    EFI_GUID Acpi20TableGuid = ACPI_20_TABLE_GUID; // ACPI 2.0 GUID
    EFI_GUID AcpiTableGuid = ACPI_TABLE_GUID;      // ACPI 1.0 GUID

    *RSDP = NULL; // Initialize RSDP to NULL

    ConfigTable = SystemTable->ConfigurationTable;
    for (UINTN Index = 0; Index < SystemTable->NumberOfTableEntries; Index++) {
        if (GuidsAreEqual(&ConfigTable[Index].VendorGuid, &Acpi20TableGuid) ||
            GuidsAreEqual(&ConfigTable[Index].VendorGuid, &AcpiTableGuid)) {
            *RSDP = ConfigTable[Index].VendorTable;
            return EFI_SUCCESS;
        }
    }

    return EFI_NOT_FOUND; // Return an error if RSDP is not found
}

// This is necessary because Clang will ignore __attribute__((sysv_abi)) as we are compiling for Windows
void CallWithSystemVAbi(void (*func)(void*), void* arg) {
    __asm__ __volatile__ (
                          "mov %0, %%rdi\n\t"   // Move the argument (void*) into RDI (1st argument register in System V ABI)
                          "mov %1, %%rax\n\t"   // Move the function pointer into RAX (function address register)
                          "call *%%rax\n\t"     // Call the function at the address in RAX
                          :
                          : "r" (arg), "r" (func)  // Inputs: function pointer and argument (both can go into any register)
                          : "%rax", "%rdi"         // Clobbered registers
                          );
}

EFI_TIME GetCurrentTime(EFI_SYSTEM_TABLE* SystemTable) 
{
    EFI_TIME CurrentTime;
    SystemTable->RuntimeServices->GetTime(&CurrentTime, NULL);

    return CurrentTime;
}

EFI_STATUS EFIAPI 
EfiMain(EFI_HANDLE Image, EFI_SYSTEM_TABLE* SystemTable) 
{
    SystemTable->ConOut->OutputString(SystemTable->ConOut, L"Hello"); 
    
    system_info System = {};
    System.Screen = GetScreenBuffer(SystemTable);

    GetRSDP(SystemTable, &System.RSDP);
    
    EFI_FILE* KernelFile = LoadFile(L"Kernel.elf", Image, SystemTable);
    
    void* EntryPoint = LoadKernel(KernelFile, SystemTable);
    
    //Get Memory Map
    UINTN MemoryMapSize = 0;
    UINTN DescriptorSize = 0;
    SystemTable->BootServices->GetMemoryMap(&MemoryMapSize, 0, 0, &DescriptorSize, 0);
    
    MemoryMapSize += 2 * DescriptorSize;

    u8* UEFIMemoryMap = 0;
    SystemTable->BootServices->AllocatePool(EfiLoaderData, MemoryMapSize, (void**) &UEFIMemoryMap);
    
    UINTN MapKey = 0;
    SystemTable->BootServices->GetMemoryMap(&MemoryMapSize, (EFI_MEMORY_DESCRIPTOR*) UEFIMemoryMap, &MapKey, &DescriptorSize, 0);
    
    System.MemoryMap = UEFIMemoryMap;
    System.MemoryMapSize = MemoryMapSize;
    System.MemoryMapDescriptorSize = DescriptorSize;
    System.Time = GetCurrentTime(SystemTable);

    SystemTable->BootServices->ExitBootServices(Image, MapKey);
    
    //This should not return
    CallWithSystemVAbi((void (*)())EntryPoint, (void*)&System);

    while (1);
    
    return EFI_SUCCESS;
}