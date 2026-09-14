#!/usr/bin/env python3
"""Add zh-Hans translations to selected EDK2 HII string files.

Reads the upstream .uni files from refs/edk2, appends a `#language zh-Hans`
line to every entry whose en-US text has a curated translation, and writes
the result under assets/hii-zh/ preserving the edk2-relative path. The CI
copies these over the edk2 tree before building.

Strings without a dictionary entry are left untouched (HII falls back to
en-US per string).

Usage: python3 tools/add_zh_hans.py <refs-edk2-dir> <out-dir>
"""
import os
import re
import sys

TRANSLATIONS = {
    # FrontPage / generic
    "Front Page": "首页",
    "Continue": "继续",
    "This selection will direct the system to continue to booting process":
        "此选项将使系统继续执行启动流程",
    "Select Language": "选择语言",
    "This is the option one adjusts to change the language for the current system":
        "此选项用于更改系统当前使用的语言",
    "Reset": "重启",
    "Cold reset (reboots the computer).": "冷复位（重新启动计算机）。",
    "Missing String": "缺失字符串",
    # Device Manager
    "Device Manager": "设备管理器",
    "This selection will take you to the Device Manager": "此选项将进入设备管理器",
    "Devices List": "设备列表",
    "Disk Devices": "磁盘设备",
    "Video Devices": "显示设备",
    "Network Devices": "网络设备",
    "Input Devices": "输入设备",
    "Motherboard Devices": "板载设备",
    "Other Devices": "其他设备",
    "Press ESC to exit.": "按 ESC 退出。",
    "Network Device List": "网络设备列表",
    # Boot Manager
    "Boot Manager": "启动管理器",
    "This selection will take you to the Boot Manager": "此选项将进入启动管理器",
    "Boot Manager Menu": "启动管理菜单",
    "Press any key to continue...": "按任意键继续……",
    "Use the <↑> and <↓> keys to choose a boot option, the <Enter> key to select a boot option, and the <Esc> key to exit the Boot Manager Menu.":
        "使用 <↑>/<↓> 键选择启动项，<回车> 键确认，<ESC> 键退出启动管理菜单。",
    # Boot Maintenance Manager
    "Boot Maintenance Manager": "启动维护管理器",
    "This selection will take you to the Boot Maintenance Manager":
        "此选项将进入启动维护管理器",
    "Boot Options": "启动选项",
    "Modify system boot options": "修改系统启动选项",
    "Driver Options": "驱动选项",
    "Modify boot driver options": "修改启动驱动选项",
    "Add Boot Option": "添加启动选项",
    "Delete Boot Option": "删除启动选项",
    "Change Boot Order": "更改启动顺序",
    "Add Driver Option": "添加驱动选项",
    "Delete Driver Option": "删除驱动选项",
    "Change Driver Order": "更改驱动顺序",
    "Set Boot Next Value": "设置下次启动项",
    # Boot popup
    "Please select boot device:": "请选择启动设备：",
    "↑ and ↓ to move selection": "↑↓ 移动选择",
    "ENTER to select boot device": "回车 选择启动设备",
    "ESC to exit": "ESC 退出",
    "EFI Firmware Setup": "固件设置",
    # Setup browser
    "F9=Reset to Defaults": "F9=恢复默认",
    "F10=Save": "F10=保存",
    "Failed to Save": "保存失败",
    "Please type in your password": "请输入密码",
    "Please type in your new password": "请输入新密码",
    "Please confirm your new password": "请再次输入新密码",
    "Passwords are not the same": "两次输入的密码不一致",
    "Incorrect password": "密码错误",
    "Press ENTER to continue": "按回车继续",
    "Please type in your data": "请输入数据",
    "[ Ok ]": "[ 确定 ]",
    "[Cancel]": "[ 取消 ]",
    "[ Yes ]": "[ 是 ]",
    "[ No ]": "[ 否 ]",
    "ERROR": "错误",
    "WARNING": "警告",
    "INFO": "信息",
    "Discard configuration changes": "放弃配置更改",
    "Save configuration changes": "保存配置更改",
    "Load default configuration": "载入默认配置",
    "Exit": "退出",
    "Press 'Y' to confirm, 'N'/'ESC' to ignore.": "按 'Y' 确认，'N'/'ESC' 忽略。",
    "Reconnect the controller failed!": "控制器重连失败！",
    "Reconnect is required, exit and reconnect": "需要重新连接，退出后重连",
    "Form is suppressed. Nothing is displayed.": "该表单被隐藏，无内容显示。",
    "Browser met some error, return!": "浏览器发生错误，返回！",
    "Form not found, return!": "未找到表单，返回！",
    "Not allowed to submit, return!": "不允许提交，返回！",
    # CustomizedDisplayLib footer keys
    "<Enter>=Select Entry": "<回车>=选择条目",
    "<Enter>=Complete Entry": "<回车>=完成条目",
    "Esc=Exit Entry": "ESC=退出条目",
    "Esc=Exit": "ESC=退出",
    "+/- =Adjust Value": "+/- =调整数值",
    "+ =Move Selection Up": "+ =上移选择",
    "- =Move Selection Down": "- =下移选择",
    "=Move Highlight": "=移动高亮",
    "0123456789 are valid inputs": "有效输入为 0123456789",
    "0-9 a-f are valid inputs": "有效输入为 0-9 a-f",
    "<Spacebar>Toggle Checkbox": "<空格>切换复选框",
    "Configuration changed": "配置已更改",
    "Changes have not saved. Save Changes and exit?": "配置尚未保存。保存并退出？",
    "Press 'Y' to save and exit, 'N' to discard and exit, 'ESC' to cancel.":
        "按 'Y' 保存并退出，'N' 不保存退出，'ESC' 取消。",
}

TARGETS = [
    'MdeModulePkg/Application/UiApp/FrontPageStrings.uni',
    'MdeModulePkg/Universal/DisplayEngineDxe/FormDisplayStr.uni',
    'MdeModulePkg/Library/DeviceManagerUiLib/DeviceManagerStrings.uni',
    'MdeModulePkg/Library/BootManagerUiLib/BootManagerStrings.uni',
    'MdeModulePkg/Library/BootMaintenanceManagerUiLib/BootMaintenanceManagerStrings.uni',
    'MdeModulePkg/Application/BootManagerMenuApp/BootManagerMenuStrings.uni',
]

entry_re = re.compile(r'^#string\s+(\S+)\s+#language\s+en-US\s+"(.*)"\s*$')


def translate_file(src, dst):
    lines = open(src).read().splitlines(True)
    out = []
    langdefs = 0
    added = 0
    for line in lines:
        if line.startswith('#langdef'):
            langdefs += 1
            out.append(line)
            if langdefs == 2:  # after the last standard langdef pair entry
                out.append('#langdef   zh-Hans "简体中文"\n')
            continue
        m = entry_re.match(line)
        if m:
            name, text = m.group(1), m.group(2)
            out.append(line)
            zh = TRANSLATIONS.get(text.strip())
            if zh and text.strip():
                indent = ' ' * 39
                out.append('%s#language zh-Hans  "%s"\n' % (indent, zh))
                added += 1
            continue
        out.append(line)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, 'w').write(''.join(out))
    return added


def main():
    refs, outdir = sys.argv[1], sys.argv[2]
    for rel in TARGETS:
        src = os.path.join(refs, rel)
        dst = os.path.join(outdir, rel)
        n = translate_file(src, dst)
        print('%s: %d translations' % (rel, n))


if __name__ == '__main__':
    main()
