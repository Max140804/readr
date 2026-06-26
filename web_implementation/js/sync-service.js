class SyncService {
    constructor() {
        this.isSyncing = false;
        this.progress = 0;
        this.totalFiles = 0;
        this.downloadedFiles = 0;
        this.listeners = [];
    }

    addListener(callback) {
        this.listeners.push(callback);
    }

    notifyListeners() {
        this.listeners.forEach(callback => callback({
            isSyncing: this.isSyncing,
            progress: this.progress,
            totalFiles: this.totalFiles,
            downloadedFiles: this.downloadedFiles
        }));
    }

    async syncAllMaterials() {
        if (this.isSyncing) return;
        if (!navigator.onLine) {
            console.log("Offline: Skipping sync");
            return;
        }

        this.isSyncing = true;
        this.progress = 0;

        const allUrls = [];
        COURSE_DATA.forEach(course => {
            if (course.pdfs) {
                course.pdfs.forEach(pdf => allUrls.push(pdf));
            }
            if (course.pastQuestions) {
                course.pastQuestions.forEach(pq => allUrls.push(pq));
            }
        });

        this.totalFiles = allUrls.length;
        this.downloadedFiles = 0;
        this.notifyListeners();

        for (const item of allUrls) {
            const exists = await isFileOffline(item.path);
            if (exists) {
                this.downloadedFiles++;
            } else {
                try {
                    const response = await fetch(item.path);
                    if (response.ok) {
                        const blob = await response.blob();
                        await saveFileOffline(item.path, item.title, blob);
                        this.downloadedFiles++;
                        console.log(`Synced: ${item.title}`);
                    }
                } catch (e) {
                    console.error(`Failed to sync ${item.title}:`, e);
                }
            }
            this.progress = (this.downloadedFiles / this.totalFiles) * 100;
            this.notifyListeners();
        }

        this.isSyncing = false;
        this.notifyListeners();
        localStorage.setItem('initial_sync_complete', 'true');
    }
}

const syncService = new SyncService();
