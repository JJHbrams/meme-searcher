# Local build patch

Upstream: flutter_secure_storage_windows 4.2.2 from pub.dev. Original LICENSE and source are included.

Replaced ATL conversion helpers (`CA2W` and `CW2A`) in
`windows/flutter_secure_storage_windows_plugin.cpp` with owned
`std::wstring`/`std::string` UTF-8 conversion helpers using the Windows API.
The affected values are credential target names and the credential enumeration
filter. This avoids the optional Visual Studio ATL component while preserving
the original Win32 Credential Manager calls, storage format, credential names,
and encryption algorithm. The shared Pub cache and operating-system settings
are not modified.
