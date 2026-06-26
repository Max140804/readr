// Initialize Dexie for offline file storage
const db = new Dexie("ReadrOfflineDB");

db.version(1).stores({
    materials: "path, title, blob, timestamp"
});

// Helper to save a file to IndexedDB
async function saveFileOffline(path, title, blob) {
    try {
        await db.materials.put({
            path: path,
            title: title,
            blob: blob,
            timestamp: Date.now()
        });
        return true;
    } catch (error) {
        console.error("Failed to save file offline:", error);
        return false;
    }
}

// Helper to get a file from IndexedDB
async function getFileOffline(path) {
    return await db.materials.get(path);
}

// Helper to check if file exists
async function isFileOffline(path) {
    const file = await db.materials.get(path);
    return !!file;
}

// Helper to remove a file
async function removeFileOffline(path) {
    await db.materials.delete(path);
}

// Helper to clear all cache
async function clearAllOfflineData() {
    await db.materials.clear();
}

// Helper to calculate total size
async function getOfflineCacheSize() {
    let total = 0;
    await db.materials.each(item => {
        if (item.blob) {
            total += item.blob.size;
        }
    });
    return (total / (1024 * 1024)).toFixed(2); // In MB
}
