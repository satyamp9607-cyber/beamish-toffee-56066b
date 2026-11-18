const SUPABASE_URL = "https://wnruzovxfxpqrdhvrryp.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Xg94QtLwlNM_G010UnWj7w_ZCjXYvYp";

if (!window.supabase || typeof window.supabase.createClient !== "function") {
    throw new Error("Supabase JS did not load. Check the network connection and CDN script.");
}

window.siteSupabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);

function openPendingPhotoStore() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open("website-profile-photos", 1);
        request.addEventListener("upgradeneeded", () => {
            request.result.createObjectStore("pending", { keyPath: "userId" });
        });
        request.addEventListener("success", () => resolve(request.result), { once: true });
        request.addEventListener("error", () => reject(request.error), { once: true });
    });
}

window.savePendingProfilePhoto = async (userId, file) => {
    const database = await openPendingPhotoStore();
    await new Promise((resolve, reject) => {
        const transaction = database.transaction("pending", "readwrite");
        transaction.objectStore("pending").put({ userId, file });
        transaction.addEventListener("complete", resolve, { once: true });
        transaction.addEventListener("error", () => reject(transaction.error), { once: true });
    });
    database.close();
};

window.takePendingProfilePhoto = async (userId) => {
    const database = await openPendingPhotoStore();
    const pending = await new Promise((resolve, reject) => {
        const transaction = database.transaction("pending", "readonly");
        const request = transaction.objectStore("pending").get(userId);
        request.addEventListener("success", () => resolve(request.result), { once: true });
        request.addEventListener("error", () => reject(request.error), { once: true });
    });

    if (!pending) {
        database.close();
        return null;
    }

    await new Promise((resolve, reject) => {
        const transaction = database.transaction("pending", "readwrite");
        transaction.objectStore("pending").delete(userId);
        transaction.addEventListener("complete", resolve, { once: true });
        transaction.addEventListener("error", () => reject(transaction.error), { once: true });
    });
    database.close();
    return pending.file;
};

window.uploadProfilePhoto = async (userId, file) => {
    const extension = file.type === "image/png" ? "png" :
        file.type === "image/webp" ? "webp" : "jpg";
    const path = `${userId}/${crypto.randomUUID()}.${extension}`;
    const { error: uploadError } = await window.siteSupabase.storage
        .from("profile-photos")
        .upload(path, file, { contentType: file.type, upsert: false });
    if (uploadError) {
        throw uploadError;
    }

    const { error: updateError } = await window.siteSupabase
        .from("profiles")
        .update({ photo_path: path })
        .eq("id", userId);
    if (updateError) {
        throw updateError;
    }
};

window.uploadPendingProfilePhoto = async (userId) => {
    const file = await window.takePendingProfilePhoto(userId);
    if (file) {
        await window.uploadProfilePhoto(userId, file);
    }
};
