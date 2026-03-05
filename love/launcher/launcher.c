#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrev, LPSTR cmdLine, int cmdShow) {
	char exePath[MAX_PATH];
	GetModuleFileNameA(NULL, exePath, MAX_PATH);

	/* Find directory containing the exe */
	char *lastSlash = strrchr(exePath, '\\');
	if (!lastSlash) lastSlash = strrchr(exePath, '/');
	if (lastSlash) *(lastSlash + 1) = '\0';
	else exePath[0] = '\0';

	/* Build command: love-runtime\love.exe love */
	char cmd[MAX_PATH * 2];
	snprintf(cmd, sizeof(cmd), "\"%slove-runtime\\love.exe\" \"%slove\"", exePath, exePath);

	STARTUPINFOA si;
	PROCESS_INFORMATION pi;
	ZeroMemory(&si, sizeof(si));
	si.cb = sizeof(si);
	ZeroMemory(&pi, sizeof(pi));

	if (CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
		CloseHandle(pi.hProcess);
		CloseHandle(pi.hThread);
	}
	return 0;
}
