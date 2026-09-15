/** @file
  Serial I/O for the Loongson 2K1000LA on-chip UART0.

  The platform previously inherited OvmfPkg's FDT based 16550 libraries, which
  locate the UART through the device tree handed over by QEMU.  On real
  hardware there is no such device tree while SEC and PEI run (this platform
  generates its own FDT, and only publishes it from BDS), so every library that
  used the serial port found nothing and silently produced no output: the
  firmware was mute on the debug UART from the first instruction, even though
  the port itself had already been programmed by the PMON derived SEC helpers.

  This library drives UART0 through its fixed MMIO window instead, so it works
  from the very first phase that needs it.  The register layout is the standard
  16550 one with a byte stride, which is what the SEC helpers poke directly and
  what the device tree advertises ("ns16550a").

  The QEMU regression target keeps the OvmfPkg FDT library: the QEMU virt
  machine places its console UART at 0x1fe001e0, not at the SoC address this
  library uses.

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent

**/

#include <Base.h>
#include <Library/BaseLib.h>
#include <Library/IoLib.h>
#include <Library/SerialPortLib.h>
#include <Protocol/SerialIo.h>

#include <Library/Loongson2K1000.h>

//
// 16550 register offsets (byte stride).
//
#define UART_RBR  0x00  // Receive buffer, read
#define UART_THR  0x00  // Transmit holding, write
#define UART_DLL  0x00  // Divisor latch low,  when DLAB is set
#define UART_IER  0x01  // Interrupt enable,   when DLAB is clear
#define UART_DLM  0x01  // Divisor latch high, when DLAB is set
#define UART_FCR  0x02  // FIFO control, write
#define UART_LCR  0x03  // Line control
#define UART_MCR  0x04  // Modem control
#define UART_LSR  0x05  // Line status
#define UART_MSR  0x06  // Modem status
#define UART_SCR  0x07  // Scratch

#define UART_LSR_DATA_READY  0x01
#define UART_LSR_THR_EMPTY   0x20

#define UART_LCR_8N1         0x03
#define UART_LCR_DLAB        0x80

#define UART_FCR_ENABLE_FIFO  0x01
#define UART_FCR_CLEAR_RX     0x02
#define UART_FCR_CLEAR_TX     0x04

#define UART_MCR_DTR          0x01
#define UART_MCR_RTS          0x02
#define UART_MCR_LOOP         0x10

#define UART_MSR_CTS          0x10
#define UART_MSR_DSR          0x20
#define UART_MSR_RI           0x40
#define UART_MSR_DCD          0x80

#define UART_DEFAULT_BAUD     115200
#define UART_FIFO_ENABLE      0x07

//
// The UART sits in the LoongArch uncached window, the same way the SEC helpers
// reach it.  Keep this a compile time constant: SerialPortLib is used from SEC
// onwards, before there is any HOB or handle to look an address up with.
//
#define UART_BASE  ((UINTN)LS_MMIO_UNCACHED (LS2K_UART0_BASE))

/**
  Program the divisor latches for a given baud rate.

  @param[in]  BaudRate  Baud rate to program, must not be zero.

  @retval  The 16 bit divisor that was written.
**/
STATIC
UINT16
UartSetBaud (
  IN UINTN  BaudRate
  )
{
  UINTN   Divisor;
  UINT16  Written;

  //
  // divisor = clock / (16 * baud), rounded to nearest.  For the 125 MHz APB
  // clock and 115200 baud this yields 68, the value the PMON derived SEC
  // helpers use after the PLL has been brought up.
  //
  Divisor = (LS2K_UART0_CLOCK + (8 * BaudRate)) / (16 * BaudRate);
  if (Divisor == 0) {
    Divisor = 1;
  }

  if (Divisor > 0xFFFF) {
    Divisor = 0xFFFF;
  }

  Written = (UINT16)Divisor;

  MmioWrite8 (UART_BASE + UART_LCR, UART_LCR_DLAB);
  MmioWrite8 (UART_BASE + UART_DLL, (UINT8)(Written & 0xFF));
  MmioWrite8 (UART_BASE + UART_DLM, (UINT8)(Written >> 8));
  MmioWrite8 (UART_BASE + UART_LCR, UART_LCR_8N1);

  return Written;
}

/**
  Initialize the serial device hardware: 115200 8N1, FIFOs on, no interrupts.

  @retval RETURN_SUCCESS  The serial device was initialized.
**/
RETURN_STATUS
EFIAPI
SerialPortInitialize (
  VOID
  )
{
  MmioWrite8 (UART_BASE + UART_IER, 0x00);
  UartSetBaud (UART_DEFAULT_BAUD);
  MmioWrite8 (UART_BASE + UART_FCR, UART_FIFO_ENABLE);
  MmioWrite8 (UART_BASE + UART_MCR, UART_MCR_DTR | UART_MCR_RTS);

  //
  // Drop whatever the previous phase or a reset left in the receive FIFO.
  //
  (VOID)MmioRead8 (UART_BASE + UART_RBR);
  (VOID)MmioRead8 (UART_BASE + UART_LSR);
  (VOID)MmioRead8 (UART_BASE + UART_SCR);

  return RETURN_SUCCESS;
}

/**
  Write data to the serial device.  Polled, so it is safe in every phase,
  including SEC where no interrupts are available yet.

  @param[in]  Buffer         Pointer to the data to write.
  @param[in]  NumberOfBytes  Number of bytes to write.

  @return  Number of bytes actually written.
**/
UINTN
EFIAPI
SerialPortWrite (
  IN UINT8  *Buffer,
  IN UINTN  NumberOfBytes
  )
{
  UINTN  Index;

  if ((Buffer == NULL) || (NumberOfBytes == 0)) {
    return 0;
  }

  for (Index = 0; Index < NumberOfBytes; Index++) {
    while ((MmioRead8 (UART_BASE + UART_LSR) & UART_LSR_THR_EMPTY) == 0) {
      CpuPause ();
    }

    MmioWrite8 (UART_BASE + UART_THR, Buffer[Index]);
  }

  return NumberOfBytes;
}

/**
  Read data from the serial device.

  @param[out]  Buffer         Buffer to receive the data.
  @param[in]   NumberOfBytes  Maximum number of bytes to read.

  @return  Number of bytes actually read.
**/
UINTN
EFIAPI
SerialPortRead (
  OUT UINT8  *Buffer,
  IN  UINTN  NumberOfBytes
  )
{
  UINTN  Index;

  if (Buffer == NULL) {
    return 0;
  }

  for (Index = 0; Index < NumberOfBytes; Index++) {
    if ((MmioRead8 (UART_BASE + UART_LSR) & UART_LSR_DATA_READY) == 0) {
      break;
    }

    Buffer[Index] = MmioRead8 (UART_BASE + UART_RBR);
  }

  return Index;
}

/**
  Poll the serial device for a pending character.

  @retval TRUE   A character is waiting in the receive buffer.
  @retval FALSE  No character is available.
**/
BOOLEAN
EFIAPI
SerialPortPoll (
  VOID
  )
{
  return (MmioRead8 (UART_BASE + UART_LSR) & UART_LSR_DATA_READY) != 0;
}

/**
  Set the control bits on the serial device.

  @param[in]  Control  Bit mask of EFI_SERIAL_* control bits to set.

  @retval RETURN_SUCCESS  The control bits were set.
**/
RETURN_STATUS
EFIAPI
SerialPortSetControl (
  IN UINT32  Control
  )
{
  UINT8  Mcr;

  Mcr = UART_MCR_DTR | UART_MCR_RTS;

  if ((Control & EFI_SERIAL_REQUEST_TO_SEND) == 0) {
    Mcr &= (UINT8)~UART_MCR_RTS;
  }

  if ((Control & EFI_SERIAL_DATA_TERMINAL_READY) == 0) {
    Mcr &= (UINT8)~UART_MCR_DTR;
  }

  if ((Control & EFI_SERIAL_HARDWARE_LOOPBACK_ENABLE) != 0) {
    Mcr |= UART_MCR_LOOP;
  }

  //
  // Hardware flow control and output buffers are not wired up on this SoC's
  // debug UART; accept the request and carry on.
  //
  MmioWrite8 (UART_BASE + UART_MCR, Mcr);

  return RETURN_SUCCESS;
}

/**
  Get the control bits of the serial device.

  @param[out]  Control  Receives the current EFI_SERIAL_* control bits.

  @retval RETURN_SUCCESS  The control bits were returned.
**/
RETURN_STATUS
EFIAPI
SerialPortGetControl (
  OUT UINT32  *Control
  )
{
  UINT8  Mcr;
  UINT8  Msr;

  if (Control == NULL) {
    return RETURN_INVALID_PARAMETER;
  }

  Mcr = MmioRead8 (UART_BASE + UART_MCR);
  Msr = MmioRead8 (UART_BASE + UART_MSR);

  *Control = 0;

  if ((Mcr & UART_MCR_RTS) != 0) {
    *Control |= EFI_SERIAL_REQUEST_TO_SEND;
  }

  if ((Mcr & UART_MCR_DTR) != 0) {
    *Control |= EFI_SERIAL_DATA_TERMINAL_READY;
  }

  if ((Mcr & UART_MCR_LOOP) != 0) {
    *Control |= EFI_SERIAL_HARDWARE_LOOPBACK_ENABLE;
  }

  if ((Msr & UART_MSR_CTS) != 0) {
    *Control |= EFI_SERIAL_CLEAR_TO_SEND;
  }

  if ((Msr & UART_MSR_DSR) != 0) {
    *Control |= EFI_SERIAL_DATA_SET_READY;
  }

  if ((Msr & UART_MSR_RI) != 0) {
    *Control |= EFI_SERIAL_RING_INDICATE;
  }

  if ((Msr & UART_MSR_DCD) != 0) {
    *Control |= EFI_SERIAL_CARRIER_DETECT;
  }

  return RETURN_SUCCESS;
}

/**
  Set the serial device attributes.

  Only the baud rate can actually change: the debug UART is hardwired to the
  8N1 framing this library programs.  Requests for anything else are refused
  rather than silently ignored.

  @param[in,out]  BaudRate          Baud rate to program.
  @param[in,out]  ReceiveFifoDepth  Ignored.
  @param[in,out]  Timeout           Ignored.
  @param[in,out]  Parity            Must be NoParity.
  @param[in,out]  DataBits          Must be 8.
  @param[in,out]  StopBits          Must be OneStopBit.

  @retval RETURN_SUCCESS            The attributes were set.
  @retval RETURN_INVALID_PARAMETER  A requested attribute is not supported.
**/
RETURN_STATUS
EFIAPI
SerialPortSetAttributes (
  IN OUT UINT64              *BaudRate,
  IN OUT UINT32              *ReceiveFifoDepth,
  IN OUT UINT32              *Timeout,
  IN OUT EFI_PARITY_TYPE     *Parity,
  IN OUT UINT8               *DataBits,
  IN OUT EFI_STOP_BITS_TYPE  *StopBits
  )
{
  if ((BaudRate == NULL) || (Parity == NULL) || (DataBits == NULL) || (StopBits == NULL)) {
    return RETURN_INVALID_PARAMETER;
  }

  if ((*Parity != NoParity) || (*DataBits != 8) || (*StopBits != OneStopBit)) {
    return RETURN_INVALID_PARAMETER;
  }

  if (*BaudRate == 0) {
    return RETURN_INVALID_PARAMETER;
  }

  UartSetBaud ((UINTN)*BaudRate);

  return RETURN_SUCCESS;
}
