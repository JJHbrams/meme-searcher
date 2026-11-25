#include "tray_icon.h"

#include <shellapi.h>
#include <windowsx.h>

#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 0x41;
constexpr UINT kActivateWindow = WM_APP + 0x42;
constexpr UINT kIconId = 1;
constexpr UINT kOpen = 1;
constexpr UINT kExit = 2;

NOTIFYICONDATAW IconData(HWND window) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = kIconId;
  return data;
}

UINT ChooseCommand(HWND window, POINT anchor) {
  HMENU menu = CreatePopupMenu();
  if (!menu) return 0;
  AppendMenuW(menu, MF_STRING, kOpen, L"\uC5F4\uAE30");  // Open
  AppendMenuW(menu, MF_STRING, kExit, L"\uC885\uB8CC");  // Exit
  SetMenuDefaultItem(menu, kOpen, FALSE);
  if (anchor.x == -1 && anchor.y == -1) GetCursorPos(&anchor);
  SetForegroundWindow(window);
  const UINT command = TrackPopupMenuEx(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
      anchor.x, anchor.y, window, nullptr);
  DestroyMenu(menu);
  PostMessageW(window, WM_NULL, 0, 0);
  return command;
}
}  // namespace

bool TrayIcon::RequestRestore(HWND window, bool legacy) {
  DWORD process_id = 0;
  if (!GetWindowThreadProcessId(window, &process_id)) return false;
  AllowSetForegroundWindow(process_id);
  if (!legacy) return PostMessageW(window, kActivateWindow, 0, 0) != FALSE;

  // Releases before 1.5.1 already handle a tray icon selection when hidden.
  if (!IsWindowVisible(window)) {
    return PostMessageW(window, kTrayMessage, 0, MAKELPARAM(NIN_SELECT, kIconId)) != FALSE;
  }
  if (IsIconic(window)) ShowWindowAsync(window, SW_RESTORE);
  SetForegroundWindow(window);
  return true;
}

bool TrayIcon::Add(HWND window) {
  if (active_) return true;
  auto data = IconData(window);
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_SHARED));
  wcscpy_s(data.szTip, L"Meme Snatcher");
  if (!data.hIcon || !Shell_NotifyIconW(NIM_ADD, &data)) return false;
  data.uVersion = NOTIFYICON_VERSION_4;
  if (!Shell_NotifyIconW(NIM_SETVERSION, &data)) {
    Shell_NotifyIconW(NIM_DELETE, &data);
    return false;
  }
  active_ = true;
  return true;
}

void TrayIcon::Remove(HWND window) {
  if (!active_) return;
  auto data = IconData(window);
  Shell_NotifyIconW(NIM_DELETE, &data);
  active_ = false;
}

void TrayIcon::Restore(HWND window) {
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  HWND popup = GetLastActivePopup(window);
  SetForegroundWindow(IsWindowVisible(popup) ? popup : window);
  Remove(window);
}

bool TrayIcon::HandleMessage(HWND window, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  if (message == kActivateWindow) {
    Restore(window);
    return true;
  }
  if (message == WM_CLOSE) {
    if (Add(window)) {
      ShowWindow(window, SW_HIDE);
    } else {
      // Keep the window accessible from the taskbar until Explorer is ready.
      ShowWindow(window, SW_MINIMIZE);
    }
    return true;
  }
  if (message == WM_DESTROY) Remove(window);
  if (!active_) return false;

  if (taskbar_created_ && message == taskbar_created_) {
    // Explorer lost the old icon. Keep a way back to the running window.
    Remove(window);
    if (!Add(window)) Restore(window);
    return true;
  }
  if (message != kTrayMessage || HIWORD(lparam) != kIconId) return false;
  switch (LOWORD(lparam)) {
    case NIN_SELECT:
    case NIN_KEYSELECT:
    case WM_LBUTTONUP:
      Restore(window);
      break;
    case WM_CONTEXTMENU: {
      POINT anchor{GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)};
      const UINT command = ChooseCommand(window, anchor);
      if (command == kOpen) {
        Restore(window);
      } else if (command == kExit) {
        DestroyWindow(window);
      } else {
        auto data = IconData(window);
        Shell_NotifyIconW(NIM_SETFOCUS, &data);
      }
      break;
    }
  }
  return true;
}
