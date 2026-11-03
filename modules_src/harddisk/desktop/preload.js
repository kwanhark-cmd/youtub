const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("hdShell", {
  retry: () => ipcRenderer.invoke("retry"),
  manual: (addr) => ipcRenderer.invoke("manual", addr),
});
