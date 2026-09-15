/** @file
  Loongson 2K1000LA firmware setup center, rendered with LVGL.

  A modern, fully Chinese setup UI built on LvglPkg (upstream
  YangGangUEFI/LvglPkg): system information, CPU overclocking, boot
  options and display settings - the pages a normal PC firmware offers.

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Uefi.h>

#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/PrintLib.h>
#include <Library/UefiBootManagerLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>

#include <Library/LvglLib.h>

#include <Guid/GlobalVariable.h>
#include <Protocol/GraphicsOutput.h>

/* ------------------------------------------------------------------ */
/* Fonts: generated from Noto Sans SC (SIL OFL) with lv_font_conv      */
/* ------------------------------------------------------------------ */
LV_FONT_DECLARE (lv_font_ls_setup_16);
LV_FONT_DECLARE (lv_font_ls_setup_24);

/* ------------------------------------------------------------------ */
/* Palette - dark navy with gold accents (matches the boot splash)     */
/* ------------------------------------------------------------------ */
#define CLR_BG_TOP     lv_color_hex (0x0A1024)
#define CLR_BG_BOT     lv_color_hex (0x1D2A52)
#define CLR_SIDEBAR    lv_color_hex (0x121A33)
#define CLR_CARD       lv_color_hex (0x18213C)
#define CLR_CARD_EDGE  lv_color_hex (0x2C3A63)
#define CLR_ACCENT     lv_color_hex (0xF0B450)
#define CLR_ACCENT_DIM lv_color_hex (0x6B5330)
#define CLR_TEXT       lv_color_hex (0xF2F5FF)
#define CLR_MUTED      lv_color_hex (0x9AA6C8)
#define CLR_OK         lv_color_hex (0x74D68A)

/* ------------------------------------------------------------------ */
/* CPU overclocking - shared with Platform/Loongson/Loongson2K1000Pkg  */
/* LoongsonOverclockDxe (applied to the CPU PLL on the next boot)      */
/* ------------------------------------------------------------------ */
#define OC_VAR_NAME  L"LoongsonOcCfg"

STATIC CONST EFI_GUID  mOcVarGuid = {
  0x7c8e1f2b, 0x4a3c, 0x4d4e, { 0x9d, 0x4e, 0x5f, 0x6a, 0x7b, 0x8c, 0x9d, 0x0e }
};

#define OC_COUNT  5
STATIC CONST UINT16  mOcFreq[OC_COUNT]   = { 800, 900, 1000, 1100, 1200 };
STATIC CONST UINT8   OC_DEFAULT_IDX      = 2;    /* 1000 MHz */
STATIC CONST CHAR8   *mOcTag[OC_COUNT]   = { "（降频）", "", "（默认）", "（超频）", "（超频 · 高风险）" };

STATIC UINT8  mOcSel;

/* ------------------------------------------------------------------ */
/* UI state                                                            */
/* ------------------------------------------------------------------ */
#define NAV_COUNT  5

STATIC lv_obj_t  *mNavBtn[NAV_COUNT];
STATIC lv_obj_t  *mNavLabel[NAV_COUNT];
STATIC lv_obj_t  *mPage[NAV_COUNT];
STATIC lv_obj_t  *mStatusLabel;

/* Interactive widgets per page, in navigation order (sidebar first). */
#define MAX_PAGE_ITEMS  16
#define MAX_BOOT_ITEMS  16
STATIC lv_obj_t  *mPageItems[NAV_COUNT][MAX_PAGE_ITEMS];
STATIC UINTN     mPageItemCount[NAV_COUNT];

/*
 * Keyboard focus is managed by the application itself instead of the LVGL
 * focus group: the group only navigates widgets that were added to it, and
 * the pages here come and go, so a self-managed list is easier to keep in
 * step. Keys arrive through the keypad indev's LV_EVENT_KEY callback.
 */
typedef enum {
  FOCUS_NAV = 0,
  FOCUS_OC,
  FOCUS_BOOT
} FOCUS_KIND;

#define FOCUS_MAX  (NAV_COUNT + MAX_PAGE_ITEMS)
STATIC lv_obj_t    *mFocusObj[FOCUS_MAX];
STATIC FOCUS_KIND  mFocusKind[FOCUS_MAX];
STATIC UINTN       mFocusArg[FOCUS_MAX];
STATIC UINTN       mFocusCount;
STATIC UINTN       mFocusIdx;

STATIC EFI_BOOT_MANAGER_LOAD_OPTION  *mBootOption[MAX_BOOT_ITEMS];
STATIC UINTN                          mBootOptionCount;

/* Keypad indev the key callback is attached to. */
STATIC lv_indev_t  *mKeypadIndev;
STATIC lv_obj_t  *mOcOptBtn[OC_COUNT];
STATIC lv_obj_t  *mOcOptLabel[OC_COUNT];
STATIC lv_obj_t  *mOcNotice;
STATIC lv_obj_t  *mBootNotice;
STATIC lv_obj_t  *mOcSummary;
STATIC UINTN     mActivePage;

STATIC CONST CHAR8  *mNavText[NAV_COUNT] = {
  "系统信息",
  "性能与超频",
  "启动设置",
  "显示与语言",
  "关于本机",
};

/* ------------------------------------------------------------------ */
/* EFI helpers                                                         */
/* ------------------------------------------------------------------ */

STATIC
UINT8
OcSelLoad (
  VOID
  )
{
  UINT8       Value;
  UINTN       Size;
  EFI_STATUS  Status;

  Value = OC_DEFAULT_IDX;
  Size  = sizeof (Value);
  Status = gRT->GetVariable (
                  OC_VAR_NAME,
                  (EFI_GUID *)&mOcVarGuid,
                  NULL,
                  &Size,
                  &Value
                  );
  if (EFI_ERROR (Status) || (Value >= OC_COUNT)) {
    Value = OC_DEFAULT_IDX;
  }

  return Value;
}

STATIC
VOID
OcSelSave (
  IN UINT8  Index
  )
{
  gRT->SetVariable (
         OC_VAR_NAME,
         (EFI_GUID *)&mOcVarGuid,
         EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS |
         EFI_VARIABLE_RUNTIME_ACCESS,
         sizeof (Index),
         &Index
         );
}

STATIC
UINT64
TotalMemoryMb (
  VOID
  )
{
  EFI_STATUS             Status;
  UINTN                  Size;
  UINTN                  MapKey;
  UINTN                  DescSize;
  UINT32                 DescVer;
  UINTN                  Index;
  UINT64                 Pages;
  EFI_MEMORY_DESCRIPTOR  *Map;

  Size = 0;
  Map  = NULL;
  Status = gBS->GetMemoryMap (&Size, Map, &MapKey, &DescSize, &DescVer);
  if (Status != EFI_BUFFER_TOO_SMALL) {
    return 0;
  }

  Size += 4 * DescSize;
  Map   = AllocatePool (Size);
  if (Map == NULL) {
    return 0;
  }

  Pages = 0;
  Status = gBS->GetMemoryMap (&Size, Map, &MapKey, &DescSize, &DescVer);
  if (!EFI_ERROR (Status)) {
    for (Index = 0; Index < Size / DescSize; Index++) {
      EFI_MEMORY_DESCRIPTOR  *Desc;

      Desc = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Map + Index * DescSize);
      if ((Desc->Type == EfiConventionalMemory) ||
          (Desc->Type == EfiBootServicesCode) ||
          (Desc->Type == EfiBootServicesData) ||
          (Desc->Type == EfiLoaderCode) ||
          (Desc->Type == EfiLoaderData))
      {
        Pages += Desc->NumberOfPages;
      }
    }
  }

  FreePool (Map);

  return MultU64x32 (Pages, EFI_PAGE_SIZE) / (1024 * 1024);
}

STATIC
VOID
ResolutionText (
  OUT CHAR8  *Buffer,
  IN  UINTN  BufferSize
  )
{
  EFI_STATUS                    Status;
  EFI_GRAPHICS_OUTPUT_PROTOCOL  *Gop;

  Status = gBS->LocateProtocol (&gEfiGraphicsOutputProtocolGuid, NULL, (VOID **)&Gop);
  if (EFI_ERROR (Status)) {
    AsciiSPrint (Buffer, BufferSize, "未知");
    return;
  }

  AsciiSPrint (
    Buffer,
    BufferSize,
    "%u x %u  (%u bpp)",
    Gop->Mode->Info->HorizontalResolution,
    Gop->Mode->Info->VerticalResolution,
    Gop->Mode->Info->PixelFormat == PixelBlueGreenRedReserved8BitPerColor ? 32 : 16
    );
}

STATIC
UINTN
BootOptionCount (
  VOID
  )
{
  EFI_BOOT_MANAGER_LOAD_OPTION  *Options;
  UINTN                         Count;

  Count   = 0;
  Options = EfiBootManagerGetLoadOptions (&Count, LoadOptionTypeBoot);
  if (Options != NULL) {
    EfiBootManagerFreeLoadOptions (Options, Count);
  }

  return Count;
}

/* ------------------------------------------------------------------ */
/* Small style helpers                                                 */
/* ------------------------------------------------------------------ */

STATIC
VOID
SetFont (
  IN lv_obj_t    *Obj,
  IN const lv_font_t  *Font,
  IN lv_color_t  Color
  )
{
  lv_obj_set_style_text_font (Obj, Font, 0);
  lv_obj_set_style_text_color (Obj, Color, 0);
}

STATIC
lv_obj_t *
MakeLabel (
  IN lv_obj_t        *Parent,
  IN const CHAR8     *Text,
  IN const lv_font_t *Font,
  IN lv_color_t      Color
  )
{
  lv_obj_t  *Label;

  Label = lv_label_create (Parent);
  lv_label_set_text (Label, Text);
  SetFont (Label, Font, Color);
  return Label;
}

/**
  A modern "card": rounded, slightly lighter than the background, with a
  thin edge and a small heading.
**/
STATIC
lv_obj_t *
MakeCard (
  IN lv_obj_t    *Parent,
  IN const CHAR8 *Title
  )
{
  lv_obj_t  *Card;
  lv_obj_t  *Head;

  Card = lv_obj_create (Parent);
  lv_obj_set_width (Card, lv_pct (100));
  lv_obj_set_height (Card, LV_SIZE_CONTENT);
  lv_obj_set_style_bg_color (Card, CLR_CARD, 0);
  lv_obj_set_style_bg_opa (Card, LV_OPA_COVER, 0);
  lv_obj_set_style_radius (Card, 14, 0);
  lv_obj_set_style_border_width (Card, 1, 0);
  lv_obj_set_style_border_color (Card, CLR_CARD_EDGE, 0);
  lv_obj_set_style_pad_all (Card, 18, 0);
  lv_obj_set_style_pad_row (Card, 10, 0);
  lv_obj_set_flex_flow (Card, LV_FLEX_FLOW_COLUMN);
  lv_obj_remove_flag (Card, LV_OBJ_FLAG_SCROLLABLE);

  if (Title != NULL) {
    Head = MakeLabel (Card, Title, &lv_font_ls_setup_16, CLR_ACCENT);
    lv_obj_set_style_pad_bottom (Head, 4, 0);
  }

  return Card;
}

/**
  One "key: value" row inside a card.
**/
STATIC
VOID
AddInfoRow (
  IN lv_obj_t    *Card,
  IN const CHAR8 *Key,
  IN const CHAR8 *Value
  )
{
  lv_obj_t  *Row;
  lv_obj_t  *KeyLabel;
  lv_obj_t  *ValLabel;

  Row = lv_obj_create (Card);
  lv_obj_set_width (Row, lv_pct (100));
  lv_obj_set_height (Row, LV_SIZE_CONTENT);
  lv_obj_set_style_bg_opa (Row, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width (Row, 0, 0);
  lv_obj_set_style_pad_all (Row, 0, 0);
  lv_obj_set_style_pad_column (Row, 16, 0);
  lv_obj_set_flex_flow (Row, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align (Row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_remove_flag (Row, LV_OBJ_FLAG_SCROLLABLE);

  KeyLabel = MakeLabel (Row, Key, &lv_font_ls_setup_16, CLR_MUTED);
  lv_obj_set_width (KeyLabel, 260);
  ValLabel = MakeLabel (Row, Value, &lv_font_ls_setup_16, CLR_TEXT);
  lv_obj_set_flex_grow (ValLabel, 1);
}

STATIC
VOID
UpdateStatusBar (
  VOID
  )
{
  CHAR8  Text[128];
  CHAR8  Res[64];

  ResolutionText (Res, sizeof (Res));
  AsciiSPrint (
    Text,
    sizeof (Text),
    "%u MHz  ·  %a",
    mOcFreq[mOcSel],
    Res
    );
  if (mStatusLabel != NULL) {
    lv_label_set_text (mStatusLabel, Text);
  }
}

/* ------------------------------------------------------------------ */
/* Page switching                                                      */
/* ------------------------------------------------------------------ */

STATIC
VOID
AddPageItem (
  IN UINTN     Page,
  IN lv_obj_t  *Obj
  )
{
  if (mPageItemCount[Page] < MAX_PAGE_ITEMS) {
    mPageItems[Page][mPageItemCount[Page]++] = Obj;
  }
}

STATIC
VOID
UpdateOcSummary (
  VOID
  )
{
  CHAR8  Text[96];

  if (mOcSummary == NULL) {
    return;
  }

  AsciiSPrint (Text, sizeof (Text), "额定主频 1000 MHz，当前选择 %u MHz。", mOcFreq[mOcSel]);
  lv_label_set_text (mOcSummary, Text);
}

STATIC
VOID
UpdateFocusStyles (
  VOID
  )
{
  UINTN  Index;

  for (Index = 0; Index < mFocusCount; Index++) {
    BOOLEAN  Focused = (Index == mFocusIdx);

    if (mFocusKind[Index] == FOCUS_NAV) {
      lv_obj_set_style_border_width (mFocusObj[Index], Focused ? 2 : 0, 0);
      lv_obj_set_style_border_color (mFocusObj[Index], CLR_TEXT, 0);
    } else {
      lv_obj_set_style_border_width (mFocusObj[Index], Focused ? 2 : 1, 0);
      lv_obj_set_style_border_color (
        mFocusObj[Index],
        Focused ? CLR_ACCENT : CLR_CARD_EDGE,
        0
        );
    }
  }
}

STATIC
VOID
RebuildFocusList (
  VOID
  )
{
  UINTN  Index;

  mFocusCount = 0;

  for (Index = 0; Index < NAV_COUNT; Index++) {
    mFocusObj[mFocusCount]  = mNavBtn[Index];
    mFocusKind[mFocusCount] = FOCUS_NAV;
    mFocusArg[mFocusCount]  = Index;
    mFocusCount++;
  }

  for (Index = 0; Index < mPageItemCount[mActivePage]; Index++) {
    mFocusObj[mFocusCount]  = mPageItems[mActivePage][Index];
    mFocusKind[mFocusCount] = (FOCUS_KIND)(mActivePage == 1 ? FOCUS_OC : FOCUS_BOOT);
    mFocusArg[mFocusCount]  = Index;
    mFocusCount++;
  }

  if (mFocusIdx >= mFocusCount) {
    mFocusIdx = 0;
  }

  UpdateFocusStyles ();
}

STATIC
VOID
RestyleNav (
  IN UINTN  Active
  )
{
  UINTN  Index;

  for (Index = 0; Index < NAV_COUNT; Index++) {
    if (Index == Active) {
      lv_obj_set_style_bg_color (mNavBtn[Index], CLR_ACCENT, 0);
      lv_obj_set_style_bg_opa (mNavBtn[Index], LV_OPA_COVER, 0);
      lv_obj_set_style_text_color (mNavLabel[Index], lv_color_hex (0x101828), 0);
    } else {
      lv_obj_set_style_bg_opa (mNavBtn[Index], LV_OPA_TRANSP, 0);
      lv_obj_set_style_text_color (mNavLabel[Index], CLR_TEXT, 0);
    }
  }
}

STATIC
VOID
ShowPage (
  IN UINTN  Index
  )
{
  UINTN  Loop;

  if (Index >= NAV_COUNT) {
    return;
  }

  mActivePage = Index;

  for (Loop = 0; Loop < NAV_COUNT; Loop++) {
    if (Loop == Index) {
      lv_obj_remove_flag (mPage[Loop], LV_OBJ_FLAG_HIDDEN);
    } else {
      lv_obj_add_flag (mPage[Loop], LV_OBJ_FLAG_HIDDEN);
    }
  }

  RestyleNav (Index);

  mFocusIdx = Index;
  RebuildFocusList ();
  UpdateFocusStyles ();
}

STATIC
VOID
RestyleOcOptions (
  VOID
  );

STATIC
VOID
UpdateOcSummary (
  VOID
  );

STATIC
VOID
OcSelect (
  IN UINTN  Index
  )
{
  if (Index >= OC_COUNT) {
    return;
  }

  mOcSel = (UINT8)Index;
  OcSelSave (mOcSel);
  RestyleOcOptions ();
  UpdateStatusBar ();
  UpdateOcSummary ();
  lv_label_set_text (mOcNotice, "已保存。CPU 主频将在下次启动时生效。");
}

STATIC
VOID
BootSetNext (
  IN UINTN  Index
  )
{
  EFI_STATUS  Status;
  CHAR8       Text[192];
  UINT16      Next;

  if (Index >= mBootOptionCount) {
    return;
  }

  CHAR8  Name[128];

  Name[0] = '\0';
  UnicodeStrToAsciiStrS (mBootOption[Index]->Description, Name, sizeof (Name));

  Next   = mBootOption[Index]->OptionNumber;
  Status = gRT->SetVariable (
                  L"BootNext",
                  &gEfiGlobalVariableGuid,
                  EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS |
                  EFI_VARIABLE_RUNTIME_ACCESS,
                  sizeof (Next),
                  &Next
                  );

  if (EFI_ERROR (Status)) {
    AsciiSPrint (Text, sizeof (Text), "设置失败：%r", Status);
  } else {
    AsciiSPrint (Text, sizeof (Text), "已设为下次启动：%a", Name);
  }

  if (mBootNotice != NULL) {
    lv_label_set_text (mBootNotice, Text);
  }
}

STATIC
VOID
ActivateFocused (
  VOID
  )
{
  if (mFocusCount == 0) {
    return;
  }

  switch (mFocusKind[mFocusIdx]) {
    case FOCUS_NAV:
      ShowPage (mFocusArg[mFocusIdx]);
      break;

    case FOCUS_OC:
      OcSelect (mFocusArg[mFocusIdx]);
      break;

    case FOCUS_BOOT:
      BootSetNext (mFocusArg[mFocusIdx]);
      break;
  }
}

/**
  Key handling: with no LVGL focus group the keypad indev reports its key
  presses through LV_EVENT_PRESSED, and the key itself is read back from the
  indev (the event parameter is NULL for indev-level events).

  Arrow keys move the focus, Enter activates the focused entry.
**/
STATIC
VOID
KeyHandler (
  IN lv_event_t  *Event
  )
{
  UINT32  Key;

  if (mKeypadIndev == NULL) {
    return;
  }

  Key = lv_indev_get_key (mKeypadIndev);

  switch (Key) {
    case LV_KEY_UP:
    case LV_KEY_LEFT:
      if (mFocusIdx == 0) {
        mFocusIdx = mFocusCount - 1;
      } else {
        mFocusIdx--;
      }

      UpdateFocusStyles ();
      break;

    case LV_KEY_DOWN:
    case LV_KEY_RIGHT:
    case LV_KEY_NEXT:
      mFocusIdx = (mFocusIdx + 1) % mFocusCount;
      UpdateFocusStyles ();
      break;

    case LV_KEY_ENTER:
      ActivateFocused ();
      break;

    default:
      break;
  }
}

STATIC
VOID
NavClickHandler (
  IN lv_event_t  *Event
  )
{
  lv_obj_t  *Target;
  UINTN     Index;

  Target = lv_event_get_target_obj (Event);

  for (Index = 0; Index < NAV_COUNT; Index++) {
    if (mNavBtn[Index] == Target) {
      ShowPage (Index);
      return;
    }
  }
}

/* ------------------------------------------------------------------ */
/* CPU overclocking page                                               */
/* ------------------------------------------------------------------ */

STATIC
VOID
RestyleOcOptions (
  VOID
  )
{
  UINTN  Index;

  for (Index = 0; Index < OC_COUNT; Index++) {
    CHAR8  Text[64];

    if (Index == mOcSel) {
      lv_obj_set_style_bg_color (mOcOptBtn[Index], CLR_ACCENT_DIM, 0);
      lv_obj_set_style_border_color (mOcOptBtn[Index], CLR_ACCENT, 0);
      lv_obj_set_style_text_color (mOcOptLabel[Index], CLR_ACCENT, 0);
    } else {
      lv_obj_set_style_bg_color (mOcOptBtn[Index], CLR_BG_TOP, 0);
      lv_obj_set_style_border_color (mOcOptBtn[Index], CLR_CARD_EDGE, 0);
      lv_obj_set_style_text_color (mOcOptLabel[Index], CLR_TEXT, 0);
    }

    AsciiSPrint (
      Text,
      sizeof (Text),
      "%u MHz%a",
      mOcFreq[Index],
      mOcTag[Index]
      );
    lv_label_set_text (mOcOptLabel[Index], Text);
  }
}

STATIC
VOID
OcClickHandler (
  IN lv_event_t  *Event
  )
{
  lv_obj_t  *Target;
  UINTN     Index;

  Target = lv_event_get_target_obj (Event);

  for (Index = 0; Index < OC_COUNT; Index++) {
    if (mOcOptBtn[Index] == Target) {
      OcSelect (Index);
      return;
    }
  }
}

STATIC
VOID
BuildPageOverclock (
  IN lv_obj_t  *Page
  )
{
  lv_obj_t  *Card;
  lv_obj_t  *Hint;
  UINTN     Index;
  CHAR8     Text[96];

  Card = MakeCard (Page, "CPU 主频");
  for (Index = 0; Index < OC_COUNT; Index++) {
    lv_obj_t  *Btn;

    Btn = lv_button_create (Card);
    lv_obj_set_width (Btn, lv_pct (100));
    lv_obj_set_height (Btn, 46);
    lv_obj_set_style_radius (Btn, 10, 0);
    lv_obj_set_style_border_width (Btn, 1, 0);
    lv_obj_set_style_bg_opa (Btn, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width (Btn, 0, 0);

    mOcOptBtn[Index]   = Btn;
    mOcOptLabel[Index] = MakeLabel (Btn, "", &lv_font_ls_setup_16, CLR_TEXT);
    lv_obj_center (mOcOptLabel[Index]);
    lv_obj_add_event_cb (Btn, OcClickHandler, LV_EVENT_CLICKED, NULL);
    AddPageItem (1, Btn);
  }

  RestyleOcOptions ();

  mOcNotice = MakeLabel (Card, "选择一个频率，设置会立即保存，并在下次启动时应用。", &lv_font_ls_setup_16, CLR_OK);
  lv_label_set_text (mOcNotice, "选择一个频率，设置会立即保存，并在下次启动时应用。");

  Card = MakeCard (Page, "说明");
  Hint = MakeLabel (
           Card,
           "1000 MHz 为 LA264 的额定主频。1100 MHz / 1200 MHz 属于超频范围，",
           &lv_font_ls_setup_16,
           CLR_MUTED
           );
  (VOID)Hint;
  MakeLabel (
    Card,
    "可能造成系统不稳定；如无法启动，请断电后重新烧写固件或恢复默认设置。",
    &lv_font_ls_setup_16,
    CLR_MUTED
    );

  mOcSummary = MakeLabel (Card, "", &lv_font_ls_setup_16, CLR_TEXT);
  UpdateOcSummary ();

  //
  // What PMON exposes for this SoC, and what the firmware can change.
  //
  Card = MakeCard (Page, "PMON 参数对照");
  AddInfoRow (Card, "CPU 频率", "可调：本页选择，启动时写入 CPU PLL");
  AddInfoRow (Card, "CPU 电压", "板级电源固定，PMON 无软件调压");
  AddInfoRow (Card, "DDR 频率", "400 MHz 编译期常量，与 PMON 一致");
  AddInfoRow (Card, "GPU / 显示 / 网口时钟", "编译期常量，与 PMON 同源");
  AddInfoRow (Card, "串口 / SPI 速率", "固定（串口 115200 8N1）");
  AddInfoRow (Card, "PCIe / USB / SATA", "由 UEFI 驱动枚举并初始化");
}

/* ------------------------------------------------------------------ */
/* Boot options page                                                   */
/* ------------------------------------------------------------------ */

STATIC
VOID
BootOptionClickHandler (
  IN lv_event_t  *Event
  )
{
  UINTN  Index;

  for (Index = 0; Index < mBootOptionCount; Index++) {
    if (mBootOption[Index] == (EFI_BOOT_MANAGER_LOAD_OPTION *)lv_event_get_user_data (Event)) {
      BootSetNext (Index);
      return;
    }
  }
}

STATIC
VOID
BuildPageBoot (
  IN lv_obj_t  *Page
  )
{
  EFI_BOOT_MANAGER_LOAD_OPTION  *Options;
  UINTN                         Count;
  UINTN                         Index;
  lv_obj_t                      *Card;
  CHAR8                         Text[192];

  Card = MakeCard (Page, "启动选项");
  MakeLabel (Card, "选择一个启动项，将其设为“下次启动”。", &lv_font_ls_setup_16, CLR_MUTED);

  mBootNotice = MakeLabel (Card, "尚未修改启动顺序。", &lv_font_ls_setup_16, CLR_MUTED);

  Options = EfiBootManagerGetLoadOptions (&Count, LoadOptionTypeBoot);
  if ((Options == NULL) || (Count == 0)) {
    MakeLabel (Card, "未找到可用的启动项。", &lv_font_ls_setup_16, CLR_MUTED);
    return;
  }

  mBootOptionCount = (Count < MAX_BOOT_ITEMS) ? Count : MAX_BOOT_ITEMS;

  for (Index = 0; Index < mBootOptionCount; Index++) {
    lv_obj_t  *Btn;
    lv_obj_t  *Label;
    CHAR8     Name[128];

    mBootOption[Index] = &Options[Index];

    //
    // Load option descriptions are CHAR16; convert before printing them
    // into the CHAR8 (UTF-8) string LVGL renders.
    //
    Name[0] = '\0';
    UnicodeStrToAsciiStrS (Options[Index].Description, Name, sizeof (Name));
    AsciiSPrint (Text, sizeof (Text), "%u.  %a", Index + 1, Name);

    Btn = lv_button_create (Card);
    lv_obj_set_width (Btn, lv_pct (100));
    lv_obj_set_height (Btn, 44);
    lv_obj_set_style_radius (Btn, 10, 0);
    lv_obj_set_style_bg_color (Btn, CLR_BG_TOP, 0);
    lv_obj_set_style_bg_opa (Btn, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width (Btn, 1, 0);
    lv_obj_set_style_border_color (Btn, CLR_CARD_EDGE, 0);
    lv_obj_set_style_shadow_width (Btn, 0, 0);

    Label = MakeLabel (Btn, Text, &lv_font_ls_setup_16, CLR_TEXT);
    lv_obj_align (Label, LV_ALIGN_LEFT_MID, 14, 0);

    lv_obj_add_event_cb (Btn, BootOptionClickHandler, LV_EVENT_CLICKED, &Options[Index]);
    AddPageItem (2, Btn);
  }
}

/* ------------------------------------------------------------------ */
/* Remaining pages                                                     */
/* ------------------------------------------------------------------ */

STATIC
VOID
BuildPageSystem (
  IN lv_obj_t  *Page
  )
{
  lv_obj_t  *Card;
  CHAR8     Text[128];
  CHAR8     Res[64];

  Card = MakeCard (Page, "处理器");
  AddInfoRow (Card, "型号", "龙芯 LA264 双核处理器");
  AsciiSPrint (Text, sizeof (Text), "%u MHz", mOcFreq[mOcSel]);
  AddInfoRow (Card, "主频", Text);
  AddInfoRow (Card, "指令集架构", "LoongArch64（龙架构）");
  AddInfoRow (Card, "核心数量", "2");

  Card = MakeCard (Page, "内存");
  AsciiSPrint (Text, sizeof (Text), "%lu MB", TotalMemoryMb ());
  AddInfoRow (Card, "可用容量", Text);
  AddInfoRow (Card, "类型", "DDR3（板载）");

  Card = MakeCard (Page, "固件");
  AddInfoRow (Card, "固件名称", "Loongson 2K1000LA EDK II");
  AddInfoRow (Card, "版本", "v0.3.1");
  AddInfoRow (Card, "图形界面", "LVGL（LvglPkg）");
  AddInfoRow (Card, "许可协议", "BSD-2-Clause-Patent");

  Card = MakeCard (Page, "显示");
  ResolutionText (Res, sizeof (Res));
  AddInfoRow (Card, "当前分辨率", Res);
  AddInfoRow (Card, "输出接口", "HDMI（SII9022A）");
}

STATIC
VOID
BuildPageDisplay (
  IN lv_obj_t  *Page
  )
{
  lv_obj_t  *Card;
  CHAR8     Res[64];

  Card = MakeCard (Page, "显示");
  ResolutionText (Res, sizeof (Res));
  AddInfoRow (Card, "分辨率", Res);
  AddInfoRow (Card, "自适应", "固件自动选择最大文本模式");
  AddInfoRow (Card, "界面主题", "深色 · 金色强调");

  Card = MakeCard (Page, "语言");
  AddInfoRow (Card, "界面语言", "简体中文");
  AddInfoRow (Card, "文本设置页", "简体中文 / English");
  MakeLabel (
    Card,
    "本设置界面为简体中文；传统设置页可在首页切换语言。",
    &lv_font_ls_setup_16,
    CLR_MUTED
    );
}

STATIC
VOID
BuildPageAbout (
  IN lv_obj_t  *Page
  )
{
  lv_obj_t  *Card;
  CHAR8     Text[160];

  Card = MakeCard (Page, "关于本固件");
  AddInfoRow (Card, "项目", "龙芯 2K1000LA 教育派 EDK II 移植");
  AddInfoRow (Card, "图形库", "LVGL（移植自 YangGangUEFI/LvglPkg）");
  AddInfoRow (Card, "引导固件", "EDK II（UEFI）");
  AsciiSPrint (
    Text,
    sizeof (Text),
    "检测到 %lu 个启动项",
    BootOptionCount ()
    );
  AddInfoRow (Card, "启动项", Text);

  Card = MakeCard (Page, "操作提示");
  MakeLabel (Card, "上下方向键：移动高亮；回车：确认选择。", &lv_font_ls_setup_16, CLR_MUTED);
  MakeLabel (Card, "Esc：退出设置，返回启动菜单。", &lv_font_ls_setup_16, CLR_MUTED);
  MakeLabel (Card, "所有设置即时保存，超频设置在下次启动时生效。", &lv_font_ls_setup_16, CLR_OK);
}

/* ------------------------------------------------------------------ */
/* App entry                                                           */
/* ------------------------------------------------------------------ */

STATIC
lv_obj_t *
BuildPage (
  IN lv_obj_t    *Parent,
  IN const CHAR8 *Title,
  IN const CHAR8 *SubTitle
  )
{
  lv_obj_t  *Page;

  Page = lv_obj_create (Parent);
  lv_obj_set_size (Page, lv_pct (100), lv_pct (100));
  lv_obj_set_style_bg_opa (Page, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width (Page, 0, 0);
  lv_obj_set_style_pad_all (Page, 0, 0);
  lv_obj_set_style_pad_row (Page, 12, 0);
  lv_obj_set_flex_flow (Page, LV_FLEX_FLOW_COLUMN);
  lv_obj_remove_flag (Page, LV_OBJ_FLAG_SCROLLABLE);

  MakeLabel (Page, Title, &lv_font_ls_setup_24, CLR_TEXT);
  if (SubTitle != NULL) {
    MakeLabel (Page, SubTitle, &lv_font_ls_setup_16, CLR_MUTED);
  }

  return Page;
}

VOID
EFIAPI
LvglSetupMain (
  VOID
  )
{
  lv_obj_t    *Root;
  lv_obj_t    *Header;
  lv_obj_t    *Body;
  lv_obj_t    *Sidebar;
  lv_obj_t    *Content;
  lv_obj_t    *Footer;
  lv_obj_t    *TitleBox;
  lv_obj_t    *Hint;
  lv_indev_t  *Indev;
  UINTN       Index;

  mOcSel      = OcSelLoad ();
  mActivePage = 0;

  /* ---------------------------------------------------------------- */
  /* Keyboard / mouse: reuse the lib-provided input devices. Arrow     */
  /* keys and Enter arrive through the keypad indev's LV_EVENT_KEY     */
  /* callback and drive the application's own focus list.              */
  /* ---------------------------------------------------------------- */
  Indev = NULL;
  for ( ; ; ) {
    Indev = lv_indev_get_next (Indev);
    if (Indev == NULL) {
      break;
    }

    if (lv_indev_get_type (Indev) == LV_INDEV_TYPE_KEYPAD) {
      mKeypadIndev = Indev;
      lv_indev_add_event_cb (Indev, KeyHandler, LV_EVENT_PRESSED, NULL);
    }
  }

  /* ---------------------------------------------------------------- */
  /* Root: vertical gradient background + top/bottom bars             */
  /* ---------------------------------------------------------------- */
  Root = lv_screen_active ();
  lv_obj_set_style_bg_color (Root, CLR_BG_TOP, 0);
  lv_obj_set_style_bg_grad_color (Root, CLR_BG_BOT, 0);
  lv_obj_set_style_bg_grad_dir (Root, LV_GRAD_DIR_VER, 0);
  lv_obj_set_style_bg_opa (Root, LV_OPA_COVER, 0);
  lv_obj_set_style_pad_all (Root, 0, 0);
  lv_obj_set_flex_flow (Root, LV_FLEX_FLOW_COLUMN);
  lv_obj_remove_flag (Root, LV_OBJ_FLAG_SCROLLABLE);

  /* ---- header ---- */
  Header = lv_obj_create (Root);
  lv_obj_set_width (Header, lv_pct (100));
  lv_obj_set_height (Header, 76);
  lv_obj_set_style_bg_opa (Header, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width (Header, 0, 0);
  lv_obj_set_style_pad_all (Header, 0, 0);
  lv_obj_set_style_pad_left (Header, 24, 0);
  lv_obj_set_style_pad_right (Header, 24, 0);
  lv_obj_set_flex_flow (Header, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align (Header, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_remove_flag (Header, LV_OBJ_FLAG_SCROLLABLE);

  TitleBox = lv_obj_create (Header);
  lv_obj_set_size (TitleBox, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_style_bg_opa (TitleBox, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width (TitleBox, 0, 0);
  lv_obj_set_style_pad_all (TitleBox, 0, 0);
  lv_obj_set_style_pad_row (TitleBox, 2, 0);
  lv_obj_set_flex_flow (TitleBox, LV_FLEX_FLOW_COLUMN);
  lv_obj_remove_flag (TitleBox, LV_OBJ_FLAG_SCROLLABLE);

  MakeLabel (TitleBox, "固件设置中心", &lv_font_ls_setup_24, CLR_TEXT);
  MakeLabel (TitleBox, "LOONGSON 2K1000LA  ·  EDK II 固件设置", &lv_font_ls_setup_16, CLR_ACCENT);

  mStatusLabel = MakeLabel (Header, "", &lv_font_ls_setup_16, CLR_MUTED);
  UpdateStatusBar ();

  /* ---- body ---- */
  Body = lv_obj_create (Root);
  lv_obj_set_width (Body, lv_pct (100));
  lv_obj_set_flex_grow (Body, 1);
  lv_obj_set_style_bg_opa (Body, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width (Body, 0, 0);
  lv_obj_set_style_pad_all (Body, 0, 0);
  lv_obj_set_style_pad_column (Body, 0, 0);
  lv_obj_set_flex_flow (Body, LV_FLEX_FLOW_ROW);
  lv_obj_remove_flag (Body, LV_OBJ_FLAG_SCROLLABLE);

  /* sidebar */
  Sidebar = lv_obj_create (Body);
  lv_obj_set_width (Sidebar, 220);
  lv_obj_set_height (Sidebar, lv_pct (100));
  lv_obj_set_style_bg_color (Sidebar, CLR_SIDEBAR, 0);
  lv_obj_set_style_bg_opa (Sidebar, LV_OPA_60, 0);
  lv_obj_set_style_radius (Sidebar, 0, 0);
  lv_obj_set_style_border_width (Sidebar, 0, 0);
  lv_obj_set_style_pad_all (Sidebar, 14, 0);
  lv_obj_set_style_pad_row (Sidebar, 8, 0);
  lv_obj_set_flex_flow (Sidebar, LV_FLEX_FLOW_COLUMN);
  lv_obj_remove_flag (Sidebar, LV_OBJ_FLAG_SCROLLABLE);

  for (Index = 0; Index < NAV_COUNT; Index++) {
    lv_obj_t  *Btn;

    Btn = lv_button_create (Sidebar);
    lv_obj_set_width (Btn, lv_pct (100));
    lv_obj_set_height (Btn, 46);
    lv_obj_set_style_radius (Btn, 12, 0);
    lv_obj_set_style_border_width (Btn, 0, 0);
    lv_obj_set_style_bg_opa (Btn, LV_OPA_TRANSP, 0);
    lv_obj_set_style_shadow_width (Btn, 0, 0);
    lv_obj_add_event_cb (Btn, NavClickHandler, LV_EVENT_CLICKED, NULL);

    mNavBtn[Index]   = Btn;
    mNavLabel[Index] = MakeLabel (Btn, mNavText[Index], &lv_font_ls_setup_16, CLR_TEXT);
    lv_obj_align (mNavLabel[Index], LV_ALIGN_LEFT_MID, 16, 0);
  }

  /* content */
  Content = lv_obj_create (Body);
  lv_obj_set_flex_grow (Content, 1);
  lv_obj_set_height (Content, lv_pct (100));
  lv_obj_set_style_bg_opa (Content, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width (Content, 0, 0);
  lv_obj_set_style_pad_all (Content, 18, 0);
  lv_obj_set_flex_flow (Content, LV_FLEX_FLOW_COLUMN);
  lv_obj_remove_flag (Content, LV_OBJ_FLAG_SCROLLABLE);

  mPage[0] = BuildPage (Content, "系统信息", "处理器、内存与固件概览");
  BuildPageSystem (mPage[0]);

  mPage[1] = BuildPage (Content, "性能与超频", "调整 CPU 主频（下次启动生效）");
  BuildPageOverclock (mPage[1]);

  mPage[2] = BuildPage (Content, "启动设置", "管理启动项");
  BuildPageBoot (mPage[2]);

  mPage[3] = BuildPage (Content, "显示与语言", "显示输出与界面语言");
  BuildPageDisplay (mPage[3]);

  mPage[4] = BuildPage (Content, "关于本机", "固件信息与操作提示");
  BuildPageAbout (mPage[4]);

  /* ---- footer ---- */
  Footer = lv_obj_create (Root);
  lv_obj_set_width (Footer, lv_pct (100));
  lv_obj_set_height (Footer, 48);
  lv_obj_set_style_bg_opa (Footer, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width (Footer, 0, 0);
  lv_obj_set_style_pad_left (Footer, 24, 0);
  lv_obj_set_style_pad_right (Footer, 24, 0);
  lv_obj_set_style_pad_all (Footer, 0, 0);
  lv_obj_set_flex_flow (Footer, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align (Footer, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_remove_flag (Footer, LV_OBJ_FLAG_SCROLLABLE);

  Hint = MakeLabel (
           Footer,
           "方向键 移动      回车 确认      Esc 退出",
           &lv_font_ls_setup_16,
           CLR_MUTED
           );
  (VOID)Hint;
  MakeLabel (Footer, "设置即时保存", &lv_font_ls_setup_16, CLR_ACCENT);

  ShowPage (0);
  mFocusIdx = 0;
  RebuildFocusList ();
  UpdateFocusStyles ();
}

/**
  Application entry point.
**/
EFI_STATUS
EFIAPI
UefiMain (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  return UefiLvglAppRegister (LvglSetupMain);
}
