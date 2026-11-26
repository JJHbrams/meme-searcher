#include "flutter_window.h"

#include <shobjidl.h>
#include <shlguid.h>
#include <shellapi.h>
#include <wincodec.h>

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "meme_version.rc2"
#include "utils.h"

namespace {

constexpr char kMediaActionsChannel[] =
    "dev.memesearcher.meme_searcher/media_actions";
constexpr UINT kQuitForUpdate = WM_APP + 0x4d;

constexpr wchar_t kPngClipboardFormat[] = L"PNG";
constexpr wchar_t kPreferredDropEffectFormat[] = L"Preferred DropEffect";
constexpr SIZE_T kMaxHeadlessClipboardBytes = 64 * 1024 * 1024;

std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return {};
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                      result.data(), size);
  return result;
}


const flutter::EncodableValue* FindValue(const flutter::EncodableMap& values,
                                         const char* key) {
  const auto found = values.find(flutter::EncodableValue(key));
  return found == values.end() ? nullptr : &found->second;
}

std::string StringArgument(const flutter::EncodableMap& values, const char* key) {
  const auto* value = FindValue(values, key);
  return value && std::holds_alternative<std::string>(*value)
             ? std::get<std::string>(*value)
             : std::string();
}

flutter::EncodableMap Success(const char* mode, const char* message) {
  return {{flutter::EncodableValue("mode"), flutter::EncodableValue(mode)},
          {flutter::EncodableValue("message"), flutter::EncodableValue(message)}};
}

struct DecodedImage {
  UINT width = 0;
  UINT height = 0;
  std::vector<BYTE> pbgra;
};

bool DecodeFirstFrame(IWICImagingFactory* factory, IWICBitmapDecoder* decoder,
                      DecodedImage* image) {
  if (!factory || !decoder || !image) return false;
  IWICBitmapFrameDecode* frame = nullptr;
  IWICFormatConverter* converter = nullptr;
  HRESULT status = decoder->GetFrame(0, &frame);
  if (SUCCEEDED(status)) status = factory->CreateFormatConverter(&converter);
  if (SUCCEEDED(status)) status = converter->Initialize(
      frame, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nullptr,
      0, WICBitmapPaletteTypeCustom);
  UINT width = 0, height = 0;
  if (SUCCEEDED(status)) status = converter->GetSize(&width, &height);
  const size_t stride = static_cast<size_t>(width) * 4;
  const size_t bytes = stride * height;
  if (SUCCEEDED(status) && width > 0 && height > 0 && width <= LONG_MAX &&
      static_cast<uint64_t>(width) * height <= 4000000 &&
      stride <= MAXUINT && bytes / height == stride && bytes <= MAXUINT) {
    image->width = width;
    image->height = height;
    image->pbgra.resize(bytes);
    status = converter->CopyPixels(nullptr, static_cast<UINT>(stride),
                                   static_cast<UINT>(bytes), image->pbgra.data());
    if (FAILED(status)) image->pbgra.clear();
  }
  if (converter) converter->Release();
  if (frame) frame->Release();
  return SUCCEEDED(status) && !image->pbgra.empty();
}

bool DecodeImageFromFile(const std::wstring& path, DecodedImage* image) {
  if (!image) return false;
  IWICImagingFactory* factory = nullptr;
  IWICBitmapDecoder* decoder = nullptr;
  HRESULT status = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&factory));
  if (SUCCEEDED(status)) {
    status = factory->CreateDecoderFromFilename(path.c_str(), nullptr,
                                                GENERIC_READ,
                                                WICDecodeMetadataCacheOnLoad,
                                                &decoder);
  }
  const bool decoded = SUCCEEDED(status) && DecodeFirstFrame(factory, decoder, image);
  if (decoder) decoder->Release();
  if (factory) factory->Release();
  return decoded;
}

bool DecodeImageFromPng(const std::vector<uint8_t>& png, DecodedImage* image) {
  if (png.empty() || png.size() > MAXDWORD || !image) return false;
  IWICImagingFactory* factory = nullptr;
  IWICStream* stream = nullptr;
  IWICBitmapDecoder* decoder = nullptr;
  HRESULT status = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&factory));
  if (SUCCEEDED(status)) status = factory->CreateStream(&stream);
  if (SUCCEEDED(status)) {
    status = stream->InitializeFromMemory(const_cast<BYTE*>(png.data()),
                                          static_cast<DWORD>(png.size()));
  }
  if (SUCCEEDED(status)) {
    status = factory->CreateDecoderFromStream(stream, nullptr,
                                              WICDecodeMetadataCacheOnLoad,
                                              &decoder);
  }
  const bool decoded = SUCCEEDED(status) && DecodeFirstFrame(factory, decoder, image);
  if (decoder) decoder->Release();
  if (stream) stream->Release();
  if (factory) factory->Release();
  return decoded;
}

HGLOBAL CopyToGlobalMemory(const void* source, size_t size) {
  if (!source || size == 0) return nullptr;
  HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size);
  if (!handle) return nullptr;
  void* destination = GlobalLock(handle);
  if (!destination) {
    GlobalFree(handle);
    return nullptr;
  }
  memcpy(destination, source, size);
  GlobalUnlock(handle);
  return handle;
}

HGLOBAL CreateClassicDib(const DecodedImage& image) {
  const size_t unpadded_row = static_cast<size_t>(image.width) * 3;
  const size_t stride = (unpadded_row + 3) & ~static_cast<size_t>(3);
  const size_t pixels = stride * image.height;
  if (image.width == 0 || image.height == 0 || image.width > LONG_MAX ||
      image.height > LONG_MAX ||
      stride < unpadded_row || pixels / image.height != stride ||
      pixels > MAXDWORD - sizeof(BITMAPINFOHEADER)) return nullptr;
  HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT,
                               sizeof(BITMAPINFOHEADER) + pixels);
  if (!handle) return nullptr;
  auto* output = static_cast<BYTE*>(GlobalLock(handle));
  if (!output) {
    GlobalFree(handle);
    return nullptr;
  }
  auto* header = reinterpret_cast<BITMAPINFOHEADER*>(output);
  header->biSize = sizeof(*header);
  header->biWidth = static_cast<LONG>(image.width);
  header->biHeight = static_cast<LONG>(image.height);  // Bottom-up, legacy-safe.
  header->biPlanes = 1;
  header->biBitCount = 24;
  header->biCompression = BI_RGB;
  header->biSizeImage = static_cast<DWORD>(pixels);
  BYTE* destination = output + sizeof(BITMAPINFOHEADER);
  for (UINT y = 0; y < image.height; ++y) {
    const BYTE* source = image.pbgra.data() +
        static_cast<size_t>(image.height - 1 - y) * image.width * 4;
    BYTE* row = destination + static_cast<size_t>(y) * stride;
    for (UINT x = 0; x < image.width; ++x) {
      const BYTE alpha = source[x * 4 + 3];
      row[x * 3] = static_cast<BYTE>(std::min(255u, source[x * 4] + 255u - alpha));
      row[x * 3 + 1] = static_cast<BYTE>(std::min(255u, source[x * 4 + 1] + 255u - alpha));
      row[x * 3 + 2] = static_cast<BYTE>(std::min(255u, source[x * 4 + 2] + 255u - alpha));
    }
  }
  GlobalUnlock(handle);
  return handle;
}

bool EncodePng(const DecodedImage& image, std::vector<uint8_t>* png) {
  if (!png || image.pbgra.empty()) return false;
  IWICImagingFactory* factory = nullptr;
  IWICBitmap* bitmap = nullptr;
  IWICBitmapEncoder* encoder = nullptr;
  IWICBitmapFrameEncode* frame = nullptr;
  IStream* stream = nullptr;
  HRESULT status = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (SUCCEEDED(status)) status = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (SUCCEEDED(status)) status = factory->CreateEncoder(GUID_ContainerFormatPng,
      nullptr, &encoder);
  if (SUCCEEDED(status)) status = encoder->Initialize(stream, WICBitmapEncoderNoCache);
  if (SUCCEEDED(status)) status = encoder->CreateNewFrame(&frame, nullptr);
  if (SUCCEEDED(status)) status = frame->Initialize(nullptr);
  if (SUCCEEDED(status)) status = frame->SetSize(image.width, image.height);
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppPBGRA;
  if (SUCCEEDED(status)) status = frame->SetPixelFormat(&format);
  const size_t stride = static_cast<size_t>(image.width) * 4;
  if (SUCCEEDED(status) && stride <= MAXUINT && image.pbgra.size() <= MAXUINT) {
    // Let the encoder negotiate its destination format, then have WIC convert
    // the explicitly-premultiplied source instead of mislabeling it as BGRA.
    status = factory->CreateBitmapFromMemory(image.width, image.height,
        GUID_WICPixelFormat32bppPBGRA, static_cast<UINT>(stride),
        static_cast<UINT>(image.pbgra.size()),
        const_cast<BYTE*>(image.pbgra.data()), &bitmap);
  }
  if (SUCCEEDED(status)) status = frame->WriteSource(bitmap, nullptr);
  if (SUCCEEDED(status)) status = frame->Commit();
  if (SUCCEEDED(status)) status = encoder->Commit();
  HGLOBAL memory = nullptr;
  if (SUCCEEDED(status)) status = GetHGlobalFromStream(stream, &memory);
  if (SUCCEEDED(status) && memory) {
    STATSTG stat = {};
    if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) || stat.cbSize.HighPart != 0 ||
        stat.cbSize.LowPart == 0) status = E_FAIL;
    const SIZE_T size = stat.cbSize.LowPart;
    const void* bytes = GlobalLock(memory);
    if (SUCCEEDED(status) && bytes && size > 0) png->assign(
        static_cast<const uint8_t*>(bytes), static_cast<const uint8_t*>(bytes) + size);
    if (bytes) GlobalUnlock(memory);
    if (png->empty()) status = E_FAIL;
  }
  if (frame) frame->Release();
  if (bitmap) bitmap->Release();
  if (encoder) encoder->Release();
  if (stream) stream->Release();
  if (factory) factory->Release();
  return SUCCEEDED(status) && !png->empty();
}

bool SetPreferredDropEffect(IDataObject* data_object) {
  const UINT format = RegisterClipboardFormatW(kPreferredDropEffectFormat);
  if (!data_object || !format) return false;
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (!memory) return false;
  auto* effect = static_cast<DWORD*>(GlobalLock(memory));
  if (!effect) {
    GlobalFree(memory);
    return false;
  }
  *effect = DROPEFFECT_COPY;
  GlobalUnlock(memory);
  FORMATETC format_etc = {static_cast<CLIPFORMAT>(format), nullptr,
                           DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  medium.tymed = TYMED_HGLOBAL;
  medium.hGlobal = memory;
  const HRESULT status = data_object->SetData(&format_etc, &medium, TRUE);
  if (FAILED(status)) GlobalFree(memory);
  return SUCCEEDED(status);
}

bool CopyShellFileToClipboard(const std::wstring& path) {
  IShellItem* item = nullptr;
  IDataObject* data_object = nullptr;
  HRESULT status = SHCreateItemFromParsingName(path.c_str(), nullptr,
                                               IID_PPV_ARGS(&item));
  if (SUCCEEDED(status)) status = item->BindToHandler(nullptr, BHID_DataObject,
                                                       IID_PPV_ARGS(&data_object));
  if (SUCCEEDED(status)) SetPreferredDropEffect(data_object);
  if (SUCCEEDED(status)) status = OleSetClipboard(data_object);
  if (SUCCEEDED(status)) status = OleFlushClipboard();
  if (data_object) data_object->Release();
  if (item) item->Release();
  return SUCCEEDED(status);
}

const std::vector<uint8_t>* BytesArgument(const flutter::EncodableMap& values,
                                          const char* key) {
  const auto* value = FindValue(values, key);
  return value && std::holds_alternative<std::vector<uint8_t>>(*value)
             ? &std::get<std::vector<uint8_t>>(*value)
             : nullptr;
}

bool IsGifMimeType(const std::string& mime, const std::wstring& path) {
  if (_stricmp(mime.c_str(), "image/gif") == 0) return true;
  const auto extension = std::filesystem::path(path).extension().wstring();
  return _wcsicmp(extension.c_str(), L".gif") == 0;
}

std::string Utf8FromUtf16(const std::wstring& value) {
  if (value.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(length, '\0');
  if (length > 0) WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), result.data(), length, nullptr, nullptr);
  return result;
}

std::string CurrentWindowStationName() {
  DWORD bytes = 0;
  HWINSTA station = GetProcessWindowStation();
  if (!station || GetUserObjectInformationW(station, UOI_NAME, nullptr, 0, &bytes) ||
      GetLastError() != ERROR_INSUFFICIENT_BUFFER || bytes < sizeof(wchar_t)) return {};
  std::vector<wchar_t> name(bytes / sizeof(wchar_t) + 1, L'\0');
  if (!GetUserObjectInformationW(station, UOI_NAME, name.data(), bytes, &bytes)) return {};
  return Utf8FromUtf16(name.data());
}

flutter::EncodableMap InspectClipboardForHeadlessTest(HWND owner) {
  flutter::EncodableMap details;
  if (!OpenClipboard(owner)) {
    details[flutter::EncodableValue("opened")] = flutter::EncodableValue(false);
    return details;
  }
  details[flutter::EncodableValue("opened")] = flutter::EncodableValue(true);
  details[flutter::EncodableValue("hasDib")] =
      flutter::EncodableValue(IsClipboardFormatAvailable(CF_DIB) != FALSE);
  details[flutter::EncodableValue("dibHeight")] = flutter::EncodableValue(int64_t{0});
  details[flutter::EncodableValue("dibBitCount")] = flutter::EncodableValue(int64_t{0});
  const UINT png_format = RegisterClipboardFormatW(kPngClipboardFormat);
  const HGLOBAL png = png_format ? static_cast<HGLOBAL>(GetClipboardData(png_format)) : nullptr;
  details[flutter::EncodableValue("hasPng")] = flutter::EncodableValue(png != nullptr);
  std::vector<uint8_t> png_bytes;
  if (png) {
    const SIZE_T size = GlobalSize(png);
    const auto* bytes = static_cast<const uint8_t*>(GlobalLock(png));
    if (bytes && size > 0 && size <= kMaxHeadlessClipboardBytes) {
      png_bytes.assign(bytes, bytes + size);
    }
    if (bytes) GlobalUnlock(png);
  }
  details[flutter::EncodableValue("pngBytes")] = flutter::EncodableValue(png_bytes);
  const HGLOBAL dib = static_cast<HGLOBAL>(GetClipboardData(CF_DIB));
  if (dib) {
    const auto* header = static_cast<const BITMAPINFOHEADER*>(GlobalLock(dib));
    if (header && header->biSize >= sizeof(BITMAPINFOHEADER)) {
      details[flutter::EncodableValue("dibHeight")] = flutter::EncodableValue(
          static_cast<int64_t>(header->biHeight));
      details[flutter::EncodableValue("dibBitCount")] = flutter::EncodableValue(
          static_cast<int64_t>(header->biBitCount));
    }
    if (header) GlobalUnlock(dib);
  }
  const HBITMAP bitmap = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
  BITMAP bitmap_info = {};
  details[flutter::EncodableValue("hasBitmap")] = flutter::EncodableValue(
      bitmap && GetObjectW(bitmap, sizeof(bitmap_info), &bitmap_info) != 0);
  const UINT shell_id_list = RegisterClipboardFormatW(L"Shell IDList Array");
  details[flutter::EncodableValue("hasShellIdList")] = flutter::EncodableValue(
      shell_id_list && IsClipboardFormatAvailable(shell_id_list) != FALSE);
  const UINT drop_effect_format = RegisterClipboardFormatW(kPreferredDropEffectFormat);
  const HGLOBAL drop_effect = drop_effect_format
      ? static_cast<HGLOBAL>(GetClipboardData(drop_effect_format)) : nullptr;
  int64_t drop_effect_value = 0;
  if (drop_effect && GlobalSize(drop_effect) >= sizeof(DWORD)) {
    const auto* value = static_cast<const DWORD*>(GlobalLock(drop_effect));
    if (value) drop_effect_value = *value;
    if (value) GlobalUnlock(drop_effect);
  }
  details[flutter::EncodableValue("dropEffect")] = flutter::EncodableValue(drop_effect_value);
  const auto drop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
  const UINT count = drop ? DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) : 0;
  details[flutter::EncodableValue("hasFileDrop")] =
      flutter::EncodableValue(count > 0);
  if (count > 0) {
    const UINT length = DragQueryFileW(drop, 0, nullptr, 0);
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, 0, path.data(), static_cast<UINT>(path.size()));
    path.resize(length);
    details[flutter::EncodableValue("filePath")] =
        flutter::EncodableValue(Utf8FromUtf16(path));
  }
  CloseClipboard();
  return details;
}

bool CopyToClipboard(HWND owner, const std::wstring& path, bool is_gif,
                     const std::vector<uint8_t>* fallback_png) {
  if (!IsWindow(owner)) return false;
  if (is_gif) return CopyShellFileToClipboard(path);
  DecodedImage image;
  if (!DecodeImageFromFile(path, &image) &&
      (!fallback_png || !DecodeImageFromPng(*fallback_png, &image))) return false;
  std::vector<uint8_t> encoded_png;
  const std::vector<uint8_t>* png = fallback_png && !fallback_png->empty()
      ? fallback_png : &encoded_png;
  if ((png == &encoded_png && !EncodePng(image, &encoded_png)) || png->empty()) return false;
  HGLOBAL dib = CreateClassicDib(image);
  HGLOBAL png_memory = CopyToGlobalMemory(png->data(), png->size());
  const UINT png_format = RegisterClipboardFormatW(kPngClipboardFormat);
  if (!dib || !png_memory || !png_format || !OpenClipboard(owner)) {
    if (dib) GlobalFree(dib);
    if (png_memory) GlobalFree(png_memory);
    return false;
  }
  bool copied = false;
  if (EmptyClipboard()) {
    // Keep static images image-only: file drops make some native targets paste
    // a blank attachment instead of the pixel payload.
    if (png_memory && SetClipboardData(png_format, png_memory)) {
      png_memory = nullptr;
      copied = true;
    }
    if (dib && SetClipboardData(CF_DIB, dib)) {
      dib = nullptr;
      copied = true;
    }
  }
  CloseClipboard();
  if (dib) GlobalFree(dib);
  if (png_memory) GlobalFree(png_memory);
  return copied;
}

bool SaveWithPicker(const std::wstring& source, const std::wstring& suggested_name) {
  IFileSaveDialog* dialog = nullptr;
  IShellItem* item = nullptr;
  PWSTR destination = nullptr;
  bool saved = false;
  if (FAILED(CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&dialog)))) {
    return false;
  }
  dialog->SetFileName(suggested_name.c_str());
  if (SUCCEEDED(dialog->Show(nullptr)) && SUCCEEDED(dialog->GetResult(&item)) &&
      SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &destination))) {
    saved = CopyFileW(source.c_str(), destination, FALSE) != FALSE;
  }
  if (destination) CoTaskMemFree(destination);
  if (item) item->Release();
  dialog->Release();
  return saved;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : headless_test_(IsHeadlessTestMode()), project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  media_actions_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMediaActionsChannel,
          &flutter::StandardMethodCodec::GetInstance());
  media_actions_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "getAppVersion") {
          result->Success(flutter::EncodableValue(std::string(VERSION_AS_STRING)));
          return;
        }
        if (call.method_name() == "quitForUpdate") {
          // The updater has already written its ready marker. A normal close
          // would be consumed by the close-to-tray handler, so acknowledge the
          // request first, remove the tray icon, and destroy this window.
          // Returning before Destroy keeps the Dart Future deterministic.
          if (!GetHandle() || !PostMessageW(GetHandle(), kQuitForUpdate, 0, 0)) {
            result->Error("quit_failed", "Could not schedule shutdown for update.");
            return;
          }
          result->Success();
          return;
        }
        const HWND owner = flutter_controller_ && flutter_controller_->view()
                               ? flutter_controller_->view()->GetNativeWindow()
                               : nullptr;
        if (call.method_name() == "debugClipboardState") {
          if (!IsHeadlessTestMode()) {
            result->Error("test_only", "Clipboard inspection is available only to headless tests.");
            return;
          }
          result->Success(InspectClipboardForHeadlessTest(owner));
          return;
        }
        if (call.method_name() == "debugWindowStation") {
          if (!IsHeadlessTestMode()) {
            result->Error("test_only", "Window-station inspection is available only to headless tests.");
            return;
          }
          result->Success(flutter::EncodableValue(CurrentWindowStationName()));
          return;
        }
        const auto* arguments = call.arguments();
        if (!arguments || !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          result->Error("invalid_file", "The original file was not found.");
          return;
        }
        const auto& values = std::get<flutter::EncodableMap>(*arguments);
        const std::string path_arg = StringArgument(values, "path");
        const std::wstring path = Utf16FromUtf8(path_arg);
        if (path.empty() || !std::filesystem::is_regular_file(path)) {
          result->Error("invalid_file", "The original file was not found.");
          return;
        }
        if (call.method_name() == "copy" || call.method_name() == "copyFile") {
          const bool original_file = call.method_name() == "copyFile";
          const bool copied = original_file
              ? CopyShellFileToClipboard(path)
              : CopyToClipboard(owner, path,
                  IsGifMimeType(StringArgument(values, "mime"), path),
                  BytesArgument(values, "clipboardPng"));
          if (!copied) {
            result->Error("clipboard_failed", "Could not copy the original file.");
            return;
          }
          result->Success(Success("clipboard", "Copied the original file."));
          return;
        }
        if (call.method_name() == "save") {
          const std::wstring name = Utf16FromUtf8(StringArgument(values, "name"));
          if (SaveWithPicker(path, name.empty() ? std::filesystem::path(path).filename().wstring() : name)) {
            result->Success(Success("save", "Saved the original file."));
          } else {
            result->Error("save_failed", "Could not save the original file.");
          }
          return;
        }
        if (call.method_name() == "share") {
          result->Error("unsupported", "Use copy or save on Windows.");
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!headless_test_ && !tray_icon_.active()) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  media_actions_channel_.reset();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kQuitForUpdate) {
    // WM_DESTROY removes the tray icon through its usual message handler.
    SetQuitOnClose(true);
    Destroy();
    return 0;
  }
  if (!headless_test_ && tray_icon_.HandleMessage(hwnd, message, wparam, lparam)) {
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
