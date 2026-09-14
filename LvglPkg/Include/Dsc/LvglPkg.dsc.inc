## @file
#  Platform DSC integration fragment for LvglPkg.
#
#  Include this file at DSC top level.  The platform must remove its stock
#  DisplayEngineDxe component before including this fragment.
#
#  Copyright (c) 2026, Hamit Karaca. All rights reserved.<BR>
#
#  SPDX-License-Identifier: BSD-2-Clause-Patent
#
##

[LibraryClasses]
  LvglLib|LvglPkg/Library/LvglLib/LvglLib.inf
  LvglThemeLib|LvglPkg/Library/LvglThemeLib/LvglThemeLib.inf
  LvglUiConfigLib|LvglPkg/Library/LvglUiConfigLib/LvglUiConfigLib.inf

[Components]
  LvglPkg/LvglDisplayEngineDxe/LvglDisplayEngineDxe.inf
  LvglPkg/LvglSetupDxe/LvglSetupDxe.inf
