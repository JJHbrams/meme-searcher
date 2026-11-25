#include "graphics_compatibility.h"

#include <string_view>

bool HasAffectedDisplayDriver() {
  constexpr std::wstring_view kMachine = L"\\Registry\\Machine\\";
  constexpr std::wstring_view kNvidia = L"PCI\\VEN_10DE&";
  for (DWORD index = 0;; ++index) {
    DISPLAY_DEVICEW display{};
    display.cb = sizeof(display);
    if (!EnumDisplayDevicesW(nullptr, index, &display, 0)) return false;
    if (!(display.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) ||
        _wcsnicmp(display.DeviceID, kNvidia.data(), kNvidia.size()) != 0 ||
        _wcsnicmp(display.DeviceKey, kMachine.data(), kMachine.size()) != 0) {
      continue;
    }
    wchar_t version[64]{};
    DWORD bytes = sizeof(version);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, display.DeviceKey + kMachine.size(),
                     L"DriverVersion", RRF_RT_REG_SZ, nullptr, version,
                     &bytes) == ERROR_SUCCESS &&
        std::wstring_view(version) == L"32.0.16.1088") {
      return true;
    }
  }
}

ScopedWarpProfile::ScopedWarpProfile(bool enabled) {
  if (!enabled) return;
  std::wstring path(32768, L'\0');
  const auto length = GetModuleFileNameW(nullptr, path.data(),
                                         static_cast<DWORD>(path.size()));
  if (!length || length >= path.size()) return;
  path.resize(length);
  CharLowerBuffW(path.data(), length);

  for (DWORD index = 0; index < 4096; ++index) {
    const std::wstring name = L"Software\\Microsoft\\Direct3D\\Application" +
                              std::to_wstring(index);
    HKEY key = nullptr;
    DWORD disposition = 0;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, name.c_str(), 0, nullptr,
                        REG_OPTION_VOLATILE, KEY_READ | KEY_SET_VALUE, nullptr,
                        &key, &disposition) != ERROR_SUCCESS) return;
    if (disposition == REG_OPENED_EXISTING_KEY) {
      std::wstring registered_path(path.size() + 1, L'\0');
      DWORD bytes = static_cast<DWORD>(registered_path.size() * sizeof(wchar_t));
      const bool already_configured =
          RegGetValueW(key, nullptr, L"Name", RRF_RT_REG_SZ, nullptr,
                       registered_path.data(), &bytes) == ERROR_SUCCESS &&
          _wcsicmp(registered_path.c_str(), path.c_str()) == 0;
      RegCloseKey(key);
      if (already_configured) return;
      continue;
    }
    entry_ = key;
    key_name_ = name;
    constexpr wchar_t kWarp[] = L"ForceWARP=1";
    if (RegSetValueExW(key, L"D3DBehaviors", 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(kWarp),
                       sizeof(kWarp)) == ERROR_SUCCESS) {
      // Write the path last so the rule is fully specified when it matches.
      RegSetValueExW(key, L"Name", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(path.c_str()),
                     (length + 1) * sizeof(wchar_t));
    }
    return;
  }
}

ScopedWarpProfile::~ScopedWarpProfile() {
  if (!entry_) return;
  RegDeleteKeyW(HKEY_CURRENT_USER, key_name_.c_str());
  RegCloseKey(entry_);
}
