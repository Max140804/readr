// Supabase Initialization
const SUPABASE_URL = 'https://hcqaseovlciadogewnsw.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhjcWFzZW92bGNpYWRvZ2V3bnN3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDczMjYsImV4cCI6MjA5NTI4MzMyNn0.HUeREBkAYeZYyv9ekq5a0kVuhpAgFTJJzydzau8Zrdk';
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// State Management
let currentPage = 'home';
let isDarkMode = localStorage.getItem('theme') === 'dark' || (window.matchMedia('(prefers-color-scheme: dark)').matches && !localStorage.getItem('theme'));
let currentMaterials = [];
let currentPdf = null;
let isLockInEnabled = false;

// Initialize App
document.addEventListener('DOMContentLoaded', () => {
    checkAuth();
    initTheme();
    renderCourseGrid();
    updateGreeting();
    loadRecentActivity();
    setupSyncListener();
    registerServiceWorker();

    // Initial Sync if needed
    if (!localStorage.getItem('initial_sync_complete')) {
        syncService.syncAllMaterials();
    }
});

function checkAuth() {
    const user = JSON.parse(localStorage.getItem('readr_user'));
    if (!user) {
        showLoginPage();
    } else {
        document.getElementById('user-name').innerText = user.name;
        document.getElementById('drawer-user-name').innerText = user.name;
        const avatar = document.getElementById('header-avatar');
        if (avatar) avatar.innerText = user.name[0];
        const drawerAvatar = document.getElementById('drawer-avatar');
        if (drawerAvatar) drawerAvatar.innerText = user.name[0];

        // Fetch remote data for already logged in user
        fetchRemoteUserData(user.id).then(() => {
            // Re-initialize theme in case it changed
            isDarkMode = localStorage.getItem('theme') === 'dark';
            if (isDarkMode) {
                document.documentElement.classList.add('dark');
            } else {
                document.documentElement.classList.remove('dark');
            }
            initTheme();
        });
    }
}

function showLoginPage() {
    document.getElementById('login-modal').classList.remove('hidden');
    document.getElementById('login-modal').classList.add('flex');
}

async function handleLogin(e) {
    e.preventDefault();
    const regno = document.getElementById('login-regno').value.trim();
    const password = document.getElementById('login-password').value.trim();

    if (!regno || !password) {
        alert("Please fill all fields");
        return;
    }

    const searchId = regno.toUpperCase().split('@')[0].replace(/\s+/g, '');
    let identity = null;

    if (searchId === 'ADMIN') {
        identity = { regNumber: 'ADMIN', surname: 'ADMIN', firstName: 'Administrator' };
    } else if (searchId === 'DEV') {
        identity = { regNumber: 'DEV', surname: 'DEV', firstName: 'Developer' };
    } else {
        identity = STUDENT_DATA.find(s => s.regNumber.toUpperCase().replace(/\s+/g, '') === searchId);
    }

    if (!identity) {
        alert('Record not found for "' + searchId + '".');
        return;
    }

    // Password validation
    const hasAdminOverride = password === 'adminwas3';
    const hasDevOverride = password === 'devmaxx';
    let expectedPassword;

    if (identity.regNumber === 'ADMIN' || hasAdminOverride) {
        expectedPassword = 'adminwas3';
    } else if (identity.regNumber === 'DEV' || hasDevOverride) {
        expectedPassword = 'devmaxx';
    } else {
        expectedPassword = identity.surname.replace(/\s+/g, '').toLowerCase() + '123';
    }

    if (password !== expectedPassword) {
        alert('Invalid Password.');
        return;
    }

    const isAdmin = identity.regNumber === 'ADMIN' || hasAdminOverride;
    const isDev = identity.regNumber === 'DEV' || hasDevOverride;
    const effectiveUserId = identity.regNumber;

    const user = {
        name: identity.firstName,
        regno: identity.regNumber,
        id: effectiveUserId,
        isAdmin: isAdmin,
        isDev: isDev
    };

    localStorage.setItem('readr_user', JSON.stringify(user));

    // Perform background auth (silent)
    const loginEmail = isAdmin ? 'admin@readr.com' : isDev ? 'dev@readr.com' : `${identity.regNumber.replace(/[^a-zA-Z0-9]/g, '')}@readr.com`;
    await performBackgroundAuth(loginEmail, expectedPassword, identity, isAdmin, isDev);

    // Fetch and sync data from Supabase before reloading
    await fetchRemoteUserData(effectiveUserId);

    location.reload();
}

async function fetchRemoteUserData(userId) {
    try {
        const { data, error } = await supabaseClient
            .from('user_data')
            .select('*')
            .eq('user_id', userId)
            .single();

        if (data) {
            if (data.bookmarks) localStorage.setItem('bookmarks', JSON.stringify(data.bookmarks));
            if (data.theme) localStorage.setItem('theme', data.theme);
            if (data.recent_activity) localStorage.setItem('recent_activity', JSON.stringify(data.recent_activity));
            if (data.study_alarm) localStorage.setItem('study_alarm', JSON.stringify(data.study_alarm));
        }
    } catch (e) {
        console.error("Error fetching remote data:", e);
    }
}

async function syncUserDataToSupabase() {
    const user = JSON.parse(localStorage.getItem('readr_user'));
    if (!user) return;

    const bookmarks = JSON.parse(localStorage.getItem('bookmarks') || '[]');
    const theme = localStorage.getItem('theme') || 'light';
    const recentActivity = JSON.parse(localStorage.getItem('recent_activity') || 'null');
    const studyAlarm = JSON.parse(localStorage.getItem('study_alarm') || 'null');

    try {
        await supabaseClient
            .from('user_data')
            .upsert({
                user_id: user.id,
                bookmarks: bookmarks,
                theme: theme,
                recent_activity: recentActivity,
                study_alarm: studyAlarm,
                updated_at: new Date().toISOString()
            }, { onConflict: 'user_id' });
    } catch (e) {
        console.error("Error syncing to Supabase:", e);
    }
}

async function performBackgroundAuth(email, password, identity, isAdmin, isDev) {
    try {
        await supabaseClient.auth.signInWithPassword({ email, password });
    } catch (_) {
        try {
            await supabaseClient.auth.signUp({
                email,
                password,
                options: {
                    data: {
                        full_name: `${identity.firstName} ${identity.surname}`,
                        reg_number: identity.regNumber,
                        role: isAdmin ? 'Admin' : isDev ? 'Developer' : 'Student',
                    }
                }
            });
        } catch (e) {
            console.error("Background Auth Error:", e);
        }
    }
}

function registerServiceWorker() {
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('./sw.js')
            .then(reg => console.log('SW Registered', reg))
            .catch(err => console.log('SW Error', err));
    }
}

// Theme Management
function initTheme() {
    if (isDarkMode) {
        document.documentElement.classList.add('dark');
        const themeIcon = document.getElementById('theme-icon');
        if (themeIcon) themeIcon.className = 'fa-solid fa-sun text-xl';
    }
}

function toggleDarkMode() {
    isDarkMode = !isDarkMode;
    document.documentElement.classList.toggle('dark');
    localStorage.setItem('theme', isDarkMode ? 'dark' : 'light');
    const themeIcon = document.getElementById('theme-icon');
    if (themeIcon) themeIcon.className = isDarkMode ? 'fa-solid fa-sun text-xl' : 'fa-solid fa-moon text-xl';

    syncUserDataToSupabase();
}

// Navigation
function showPage(pageId) {
    // Hide all pages
    document.querySelectorAll('.page-container').forEach(p => p.classList.add('hidden'));

    // Show target page
    const target = document.getElementById(`page-${pageId}`);
    if (target) {
        target.classList.remove('hidden');
        currentPage = pageId;
    }

    // Update Nav UI
    updateNavUI(pageId);

    // Close mobile drawer if open
    hideMobileMenu();

    if (pageId === 'forum') loadForum();
    if (pageId === 'bookmarks') renderBookmarks();
    if (pageId === 'assignments') renderAssignments();
    if (pageId === 'courses') renderAllCourses();
    if (pageId === 'timetable') renderTimetable();
}

function renderAllCourses() {
    const grid = document.getElementById('all-courses-grid');

    const sem1 = COURSE_DATA.filter(c => c.semester === 1);
    const sem2 = COURSE_DATA.filter(c => c.semester === 2);

    grid.innerHTML = `
        <div class="flex space-x-4 mb-8 bg-gray-100 dark:bg-gray-800 p-1 rounded-2xl w-fit">
            <button onclick="switchSemesterTab(1)" id="sem-tab-1" class="px-6 py-2 rounded-xl font-bold transition-all bg-white dark:bg-darkCard shadow-sm text-primary">1st Semester</button>
            <button onclick="switchSemesterTab(2)" id="sem-tab-2" class="px-6 py-2 rounded-xl font-bold transition-all text-gray-500">2nd Semester</button>
        </div>

        <div id="sem-content-1" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            ${sem1.map(course => renderCourseCard(course)).join('')}
        </div>
        <div id="sem-content-2" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 hidden">
            ${sem2.map(course => renderCourseCard(course)).join('')}
        </div>
    `;
}

function switchSemesterTab(sem) {
    const tab1 = document.getElementById('sem-tab-1');
    const tab2 = document.getElementById('sem-tab-2');
    const content1 = document.getElementById('sem-content-1');
    const content2 = document.getElementById('sem-content-2');

    if (sem === 1) {
        tab1.className = "px-6 py-2 rounded-xl font-bold transition-all bg-white dark:bg-darkCard shadow-sm text-primary";
        tab2.className = "px-6 py-2 rounded-xl font-bold transition-all text-gray-500";
        content1.classList.remove('hidden');
        content2.classList.add('hidden');
    } else {
        tab2.className = "px-6 py-2 rounded-xl font-bold transition-all bg-white dark:bg-darkCard shadow-sm text-secondary";
        tab1.className = "px-6 py-2 rounded-xl font-bold transition-all text-gray-500";
        content2.classList.remove('hidden');
        content1.classList.add('hidden');
    }
}

function renderCourseCard(course) {
    return `
        <div class="course-card" onclick="viewMaterials('${course.title}')">
            <div class="icon-wrapper">
                <i class="${course.icon} text-2xl"></i>
            </div>
            <h4 class="font-[900] text-xl mb-2">${course.title}</h4>
            <p class="text-[11px] text-slate-500 dark:text-slate-400 font-bold uppercase tracking-widest mb-6 line-clamp-1">${course.subtitle}</p>
            <div class="flex items-center text-[10px] font-[900] text-primary/60 dark:text-blue-400/60 tracking-[0.2em] uppercase mt-auto">
                <i class="fa-solid fa-bookmark mr-2 text-accent"></i>
                ${course.credits} Credits
            </div>
        </div>
    `;
}

// Timetable Rendering
function renderTimetable() {
    const container = document.getElementById('timetable-content');
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

    container.innerHTML = days.map(day => {
        const slots = TIMETABLE[day] || [];
        return `
            <div class="space-y-6">
                <h3 class="text-[10px] font-black uppercase tracking-[0.4em] text-slate-400 dark:text-slate-500 flex items-center px-2">
                    <span class="w-1 h-4 bg-primary rounded-full mr-3 shadow-[0_0_10px_rgba(0,74,173,0.5)]"></span>
                    ${day}
                </h3>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    ${slots.length > 0 ? slots.map(slot => `
                        <div class="course-card !p-6 !h-auto !rounded-[2rem]">
                            <div class="flex items-center mb-4">
                                <div class="w-12 h-12 bg-primary/5 rounded-2xl flex items-center justify-center text-primary mr-4 border border-primary/10">
                                    <i class="fa-solid fa-clock"></i>
                                </div>
                                <div>
                                    <h4 class="font-black text-slate-800 dark:text-slate-100">${slot.course}</h4>
                                    <p class="text-[10px] font-black text-slate-400 uppercase tracking-widest">${slot.time}</p>
                                </div>
                            </div>
                            <div class="flex items-center text-[10px] font-[900] text-primary/60 dark:text-blue-400/60 tracking-[0.2em] uppercase">
                                <i class="fa-solid fa-location-dot mr-2 text-accent"></i>
                                ${slot.location}
                            </div>
                        </div>
                    `).join('') : `
                        <div class="col-span-full py-8 px-8 glass rounded-[2rem] border-dashed border-2 border-slate-100 dark:border-white/5 flex items-center justify-center">
                            <p class="text-[10px] font-black text-slate-300 uppercase tracking-widest">No lectures scheduled</p>
                        </div>
                    `}
                </div>
            </div>
        `;
    }).join('');
}



// Forum Logic
function scrollToMessage(messageId) {
    const element = document.getElementById(`msg-${messageId}`);
    if (element) {
        element.scrollIntoView({ behavior: 'smooth', block: 'center' });
        const bubble = element.querySelector('.message-bubble');
        if (bubble) {
            bubble.classList.add('highlight-message');
            setTimeout(() => {
                bubble.classList.remove('highlight-message');
            }, 2000);
        }
    }
}

async function loadForum() {
    const container = document.getElementById('forum-messages');

    // Support Enter key in forum
    const forumInput = document.getElementById('forum-input');
    if (forumInput && !forumInput.dataset.listener) {
        forumInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') sendForumMessage();
        });
        forumInput.dataset.listener = 'true';
    }

    // Subscribe to real-time updates
    if (window.forumSubscription) {
        window.forumSubscription.unsubscribe();
    }

    window.forumSubscription = supabaseClient.channel('public:forum_messages')
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'forum_messages' }, payload => {
            appendForumMessage(payload.new, true);
        })
        .subscribe((status) => {
            console.log("Supabase subscription status:", status);
            if (status === 'CHANNEL_ERROR') {
                console.error("Forum subscription error, retrying...");
                setTimeout(loadForum, 5000);
            }
        });

    const { data: posts, error } = await supabaseClient
        .from('forum_messages')
        .select('*')
        .order('timestamp', { ascending: true });

    if (error) {
        console.error("Error loading forum:", error);
        return;
    }

    container.innerHTML = posts.map(post => renderForumPost(post)).join('');
    container.scrollTop = container.scrollHeight;

    // Remove red dot when viewing forum
    document.getElementById('forum-dot')?.classList.add('hidden');
    document.getElementById('alarm-dot-mobile')?.classList.add('hidden');
}

function renderForumPost(post) {
    const user = JSON.parse(localStorage.getItem('readr_user'));
    const isMe = user && post.uid && post.uid.toString() === user.id.toString();
    const time = post.timestamp ? new Date(post.timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : 'Just now';
    const senderName = post.sender || 'Anonymous';
    const messageText = post.text || '';

    return `
        <div id="msg-${post.id}" class="flex space-x-4 ${isMe ? 'flex-row-reverse space-x-reverse' : ''} group animate-premiumFade">
            <div class="w-12 h-12 ${isMe ? 'bg-primary shadow-[0_10px_20px_rgba(0,74,173,0.2)]' : 'bg-slate-200 dark:bg-slate-700'} rounded-[1.2rem] flex items-center justify-center text-white font-black flex-shrink-0 uppercase text-lg border-2 border-white dark:border-slate-800">
                ${senderName[0]}
            </div>
            <div class="max-w-[80%] md:max-w-[60%]">
                <div class="message-bubble ${isMe ? 'bg-primary text-white shadow-[0_15px_30px_rgba(0,74,173,0.1)]' : 'bg-white dark:bg-slate-800 dark:text-slate-100 shadow-sm'} p-5 rounded-[2rem] ${isMe ? 'rounded-tr-none' : 'rounded-tl-none'} border border-slate-100 dark:border-white/5 relative">
                    <p class="font-black text-[10px] uppercase tracking-widest mb-2 ${isMe ? 'text-white/60' : 'text-primary'}">${senderName}</p>
                    ${post.reply_to_name ? `
                        <div onclick="scrollToMessage('${post.reply_to_id}')" class="mb-3 p-2 bg-black/10 rounded-xl border-l-4 border-white/30 text-[11px] opacity-80 cursor-pointer hover:bg-black/20 transition-all">
                            <p class="font-bold">${post.reply_to_name}</p>
                            <p class="truncate">${post.reply_to_text || 'Attachment'}</p>
                        </div>
                    ` : ''}
                    ${post.image_url ? `<img src="${post.image_url}" class="rounded-xl mb-3 max-h-60 w-full object-cover">` : ''}
                    <p class="text-sm font-medium leading-relaxed">${messageText}</p>
                </div>
                <p class="text-[9px] font-black text-slate-400 uppercase tracking-widest mt-2 ${isMe ? 'text-right mr-3' : 'ml-3'}">${time}</p>
            </div>
        </div>
    `;
}

async function sendForumMessage() {
    const user = JSON.parse(localStorage.getItem('readr_user'));
    const input = document.getElementById('forum-input');
    const text = input.value.trim();
    if (!text || !user) return;

    const { error } = await supabaseClient
        .from('forum_messages')
        .insert([{
            text: text,
            sender: user.name,
            uid: user.id,
            timestamp: new Date().toISOString()
        }]);

    if (error) {
        alert("Failed to send message: " + error.message);
    } else {
        input.value = '';
    }
}

function appendForumMessage(post, animate = false) {
    const container = document.getElementById('forum-messages');
    const div = document.createElement('div');
    div.innerHTML = renderForumPost(post);
    container.appendChild(div.firstElementChild);
    container.scrollTop = container.scrollHeight;

    if (currentPage !== 'forum') {
        document.getElementById('forum-dot')?.classList.remove('hidden');
        document.getElementById('alarm-dot-mobile')?.classList.remove('hidden');
    }
}

// Bookmarks Logic
async function toggleBookmark(path, title) {
    let bookmarks = JSON.parse(localStorage.getItem('bookmarks') || '[]');
    const index = bookmarks.findIndex(b => b.path === path);

    if (index > -1) {
        bookmarks.splice(index, 1);
    } else {
        bookmarks.push({ path, title, date: new Date().toLocaleDateString() });
    }

    localStorage.setItem('bookmarks', JSON.stringify(bookmarks));
    if (currentPage === 'bookmarks') renderBookmarks();
    updateBookmarkButton(path);

    syncUserDataToSupabase();
}

function renderBookmarks() {
    const bookmarks = JSON.parse(localStorage.getItem('bookmarks') || '[]');
    const container = document.getElementById('bookmarks-list');

    if (bookmarks.length === 0) {
        container.innerHTML = `
            <div class="text-center py-24 glass rounded-[3rem]">
                <i class="fa-solid fa-bookmark text-7xl text-slate-100 dark:text-slate-800 mb-6"></i>
                <p class="text-slate-400 font-bold uppercase tracking-widest text-[10px]">No saved materials yet.</p>
            </div>
        `;
        return;
    }

    container.innerHTML = bookmarks.map(b => `
        <div class="course-card !flex-row items-center !p-5 !h-auto !mb-4 !rounded-[2rem]">
            <div class="flex items-center cursor-pointer flex-1" onclick="openPdf('${b.path}', '${b.title}', 'Saved')">
                <div class="icon-wrapper !mb-0 mr-5 !w-12 !h-12 !rounded-2xl bg-accent/10 border border-accent/20">
                    <i class="fa-solid fa-file-pdf text-primary"></i>
                </div>
                <div>
                    <h5 class="font-[950] text-slate-800 dark:text-slate-100 truncate">${b.title}</h5>
                    <p class="text-[9px] font-black text-slate-400 uppercase tracking-widest mt-1">Saved on ${b.date}</p>
                </div>
            </div>
            <button onclick="toggleBookmark('${b.path}', '${b.title}')" class="w-10 h-10 rounded-full flex items-center justify-center text-primary hover:bg-primary/10 transition-all">
                <i class="fa-solid fa-bookmark"></i>
            </button>
        </div>
    `).join('');
}

function toggleBookmarkInViewer() {
    if (currentPdf) {
        toggleBookmark(currentPdf.path, currentPdf.title);
    }
}

function updateBookmarkButton(path) {
    const bookmarks = JSON.parse(localStorage.getItem('bookmarks') || '[]');
    const isBookmarked = bookmarks.some(b => b.path === path);
    const icon = document.getElementById('pdf-viewer-bookmark-icon');
    if (icon) {
        icon.className = isBookmarked ? 'fa-solid fa-bookmark text-primary' : 'fa-regular fa-bookmark';
    }
}

function updateNavUI(pageId) {
    // Desktop Nav
    document.querySelectorAll('.nav-item').forEach(btn => {
        const onClick = btn.getAttribute('onclick');
        if (onClick && onClick.includes(`'${pageId}'`)) {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });

    // Mobile Nav
    document.querySelectorAll('.mobile-nav-item').forEach(btn => {
        const onClick = btn.getAttribute('onclick');
        if (onClick && onClick.includes(`'${pageId}'`)) {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });
}

// UI Rendering
function renderCourseGrid() {
    const grid = document.getElementById('course-grid');
    const sem1 = COURSE_DATA.filter(c => c.semester === 1);
    grid.innerHTML = sem1.map(course => renderCourseCard(course)).join('');
}

async function viewMaterials(courseTitle) {
    const course = COURSE_DATA.find(c => c.title === courseTitle);
    if (!course) return;

    document.getElementById('materials-title').innerText = `${course.title} Materials`;
    const listContainer = document.getElementById('materials-list');

    let html = '';

    // Lecture Materials Section
    if (course.pdfs && course.pdfs.length > 0) {
        html += `<h3 class="text-[10px] font-[950] text-slate-400 dark:text-slate-500 uppercase tracking-[0.3em] mb-6 px-2">Lecture Materials</h3>`;
        const pdfsHtml = await Promise.all(course.pdfs.map(async (pdf) => {
            const isCached = await isFileOffline(pdf.path);
            return renderMaterialItem(pdf, isCached, course.title);
        }));
        html += pdfsHtml.join('');
    }

    // Past Questions Section
    if (course.pastQuestions && course.pastQuestions.length > 0) {
        html += `<h3 class="text-[10px] font-[950] text-slate-400 dark:text-slate-500 uppercase tracking-[0.3em] mt-10 mb-6 px-2">Past Questions</h3>`;
        const pqHtml = await Promise.all(course.pastQuestions.map(async (pq) => {
            const isCached = await isFileOffline(pq.path);
            return renderMaterialItem(pq, isCached, course.title, 'fa-solid fa-paste text-blue-500');
        }));
        html += pqHtml.join('');
    }

    // Videos Section
    if (course.videos && course.videos.length > 0) {
        html += `<h3 class="text-[10px] font-[950] text-slate-400 dark:text-slate-500 uppercase tracking-[0.3em] mt-10 mb-6 px-2">Video Lessons</h3>`;
        const videosHtml = course.videos.map(video => `
            <div class="course-card !flex-row items-center !p-4 !h-auto !mb-4 !rounded-[2rem]" onclick="openVideoPlayer('${video.url}', '${video.title}')">
                <div class="w-20 h-14 bg-slate-100 dark:bg-slate-800 rounded-2xl overflow-hidden mr-5 relative flex-shrink-0">
                    <img src="${video.thumbnail}" class="w-full h-full object-cover opacity-80 group-hover:scale-110 transition-transform duration-700">
                    <div class="absolute inset-0 flex items-center justify-center bg-primary/20 backdrop-blur-[2px] opacity-0 group-hover:opacity-100 transition-opacity">
                        <i class="fa-solid fa-play text-white text-sm"></i>
                    </div>
                </div>
                <div class="flex-1 min-w-0">
                    <h5 class="font-black text-slate-800 dark:text-slate-100 truncate">${video.title}</h5>
                    <span class="text-[9px] text-primary dark:text-blue-400 font-black uppercase tracking-widest">In-app player</span>
                </div>
                <div class="w-10 h-10 rounded-full bg-primary/5 flex items-center justify-center text-primary group-hover:bg-primary group-hover:text-white transition-all">
                    <i class="fa-solid fa-play text-xs"></i>
                </div>
            </div>
        `);
        html += videosHtml.join('');
    }

    if (!html) {
        html = `<div class="text-center py-10 text-gray-400">No materials available yet.</div>`;
    }

    listContainer.innerHTML = html;
    showPage('materials');
}

function renderMaterialItem(item, isCached, courseTitle, iconClass = 'fa-solid fa-file-pdf text-red-500') {
    const isImage = item.path.match(/\.(jpg|jpeg|png|gif)$/i);
    if (isImage) iconClass = 'fa-solid fa-image text-green-500';

    return `
        <div class="course-card !flex-row items-center !p-5 !h-auto !mb-4 !rounded-[2rem]" onclick="openPdf('${item.path}', '${item.title}', '${courseTitle}')">
            <div class="icon-wrapper !mb-0 mr-5 !w-12 !h-12 !rounded-2xl bg-slate-50 dark:bg-slate-800/50">
                <i class="${iconClass} text-xl"></i>
            </div>
            <div class="flex-1 min-w-0">
                <h5 class="font-black text-slate-800 dark:text-slate-100 truncate">${item.title}</h5>
                <div class="flex items-center mt-1">
                    ${isCached ?
                        `<span class="text-[9px] text-green-500 font-black uppercase tracking-widest flex items-center"><i class="fa-solid fa-circle-check mr-1.5"></i> Offline Ready</span>` :
                        `<span class="text-[9px] text-slate-400 font-black uppercase tracking-widest">Tap to ${isImage ? 'view' : 'open'}</span>`
                    }
                </div>
            </div>
            <div class="w-8 h-8 rounded-full flex items-center justify-center text-slate-300">
                <i class="fa-solid fa-chevron-right text-xs"></i>
            </div>
        </div>
    `;
}

// PDF Viewer
async function openPdf(path, title, courseName) {
    const modal = document.getElementById('pdf-modal');
    const iframe = document.getElementById('pdf-iframe');
    const loader = document.getElementById('pdf-loader');

    currentPdf = { path, title };
    document.getElementById('pdf-viewer-title').innerText = title;
    modal.classList.remove('hidden');
    modal.classList.add('flex');
    loader.classList.remove('hidden');

    updateBookmarkButton(path);
    saveActivity(title, `Reading in ${courseName}`, path);

    try {
        const offlineFile = await getFileOffline(path);
        let url = path;

        if (offlineFile) {
            url = URL.createObjectURL(offlineFile.blob);
        } else {
            // Force a fetch to cache it for future offline use
            fetch(path)
                .then(res => res.blob())
                .then(blob => saveFileOffline(path, title, blob))
                .catch(err => console.warn("Background cache failed:", err));
        }

        // Mobile browsers (especially iOS) hate PDFs in iframes.
        // We use a Google Docs viewer fallback for better compatibility if not offline
        const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);

        if (isMobile && !offlineFile) {
            // Use Google PDF viewer for mobile web to ensure it opens
            iframe.src = `https://docs.google.com/viewer?url=${encodeURIComponent(url)}&embedded=true`;
        } else {
            iframe.src = url;
        }

    } catch (e) {
        console.error("PDF Load Error:", e);
        iframe.src = path;
    }

    iframe.onload = () => loader.classList.add('hidden');
}

function closePdf() {
    const modal = document.getElementById('pdf-modal');
    const iframe = document.getElementById('pdf-iframe');
    modal.classList.add('hidden');
    modal.classList.remove('flex');
    iframe.src = '';

    if (document.fullscreenElement) {
        document.exitFullscreen();
    }
}

function togglePdfFullscreen() {
    const modal = document.getElementById('pdf-modal');
    if (!document.fullscreenElement) {
        modal.requestFullscreen().catch(err => {
            console.error(`Error attempting to enable full-screen mode: ${err.message}`);
        });
    } else {
        document.exitFullscreen();
    }
}

// Video Player
function openVideoPlayer(url, title) {
    const modal = document.getElementById('video-modal');
    const iframe = document.getElementById('video-iframe');
    const titleEl = document.getElementById('video-modal-title');

    // Convert YouTube URL to Embed URL
    let embedUrl = url;
    try {
        if (url.includes('youtube.com/watch?v=')) {
            const videoId = new URL(url).searchParams.get('v');
            embedUrl = `https://www.youtube.com/embed/${videoId}`;
        } else if (url.includes('youtu.be/')) {
            const videoId = url.split('/').pop();
            embedUrl = `https://www.youtube.com/embed/${videoId}`;
        }
    } catch (e) {
        console.error("URL Parsing failed", e);
    }

    // Add autoplay and rel=0
    const separator = embedUrl.includes('?') ? '&' : '?';
    embedUrl += `${separator}autoplay=1&rel=0`;

    iframe.src = embedUrl;
    titleEl.innerText = title;

    modal.classList.remove('hidden');
    modal.classList.add('flex');
}

function closeVideoPlayer() {
    const modal = document.getElementById('video-modal');
    const iframe = document.getElementById('video-iframe');
    modal.classList.add('hidden');
    modal.classList.remove('flex');
    iframe.src = '';
}

// Activity Tracking
function saveActivity(title, subtitle, path) {
    const activity = { title, subtitle, path, timestamp: Date.now() };
    localStorage.setItem('recent_activity', JSON.stringify(activity));
    loadRecentActivity();

    syncUserDataToSupabase();
}

function loadRecentActivity() {
    const activity = JSON.parse(localStorage.getItem('recent_activity'));
    if (activity) {
        const container = document.getElementById('recent-activity-container');
        const title = document.getElementById('recent-title');
        const subtitle = document.getElementById('recent-subtitle');
        const card = document.getElementById('recent-card');

        if (container) container.classList.remove('hidden');
        if (title) title.innerText = activity.title;
        if (subtitle) subtitle.innerText = activity.subtitle;
        if (card) {
            card.onclick = () => openPdf(activity.path, activity.title, '');
        }
    }
}

// Timer Logic
function updateGreeting() {
    const hour = new Date().getHours();
    let greeting = "Good Evening!";
    if (hour < 12) greeting = "Good Morning!";
    else if (hour < 17) greeting = "Good Afternoon!";
    document.getElementById('greeting').innerText = greeting;
}

function startTimer() {
    updateCountdown();
    setInterval(updateCountdown, 1000);
}

function updateCountdown() {
    const now = new Date();
    const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    const today = days[now.getDay()];

    const timerText = document.getElementById('timer-text');
    const statusLabel = document.getElementById('class-status');
    const subMessage = document.getElementById('sub-message');

    if (now.getDay() === 0 || now.getDay() === 6) {
        timerText.innerText = "Weekend! 🎉";
        if (statusLabel) statusLabel.innerText = "WEEKEND MODE";
        if (subMessage) subMessage.innerText = "Enjoy your break! 🥳";
        return;
    }

    if (now.getDay() === 5) {
        timerText.innerText = "Free Day! 😎";
        if (statusLabel) statusLabel.innerText = "FRIDAY";
        if (subMessage) subMessage.innerText = "No classes today, catch up on tasks!";
        return;
    }

    const todaySchedule = TIMETABLE[today] || [];
    let nextClass = null;

    for (const item of todaySchedule) {
        const timeStr = item.time; // e.g. "8:00 AM - 10:00 AM"
        const parts = timeStr.split("-");
        const startH = parseHour(parts[0]);
        const endH = parseHour(parts[1]);

        const startTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), startH, 0);
        const endTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), endH, 0);

        if (now >= startTime && now < endTime) {
            timerText.innerText = item.course;
            if (statusLabel) statusLabel.innerText = "ONGOING CLASS";
            if (subMessage) subMessage.innerText = "Pay attention! 📚";
            return;
        }

        if (startTime > now) {
            if (!nextClass || startTime < nextClass.time) {
                nextClass = { time: startTime, course: item.course };
            }
        }
    }

    if (nextClass) {
        const diff = nextClass.time - now;
        const h = String(Math.floor(diff / 3600000)).padStart(2, '0');
        const m = String(Math.floor((diff % 3600000) / 60000)).padStart(2, '0');
        const s = String(Math.floor((diff % 60000) / 1000)).padStart(2, '0');

        timerText.innerText = `${h}:${m}:${s}`;
        if (statusLabel) statusLabel.innerText = `NEXT: ${nextClass.course}`;
        if (subMessage) subMessage.innerText = "Get ready, bub";
    } else {
        timerText.innerText = "Done! 🎉";
        if (statusLabel) statusLabel.innerText = "CLASSES OVER";
        if (subMessage) subMessage.innerText = "We go again tomorrow";
    }
}

function parseHour(timePart) {
    timePart = timePart.trim().toUpperCase();
    let hour = parseInt(timePart.split(":")[0]);
    if (timePart.includes("PM") && hour < 12) hour += 12;
    if (timePart.includes("AM") && hour === 12) hour = 0;
    return hour;
}

// Sync UI
function setupSyncListener() {
    syncService.addListener((state) => {
        const containers = [document.getElementById('sync-container'), document.getElementById('sync-indicator-mobile')];
        const percent = document.getElementById('sync-percent');
        const drawerStatus = document.getElementById('drawer-sync-status');

        if (state.isSyncing) {
            containers.forEach(c => c?.classList.remove('hidden'));
            if (percent) percent.innerText = `${Math.round(state.progress)}%`;
            if (drawerStatus) drawerStatus.innerText = `Syncing: ${Math.round(state.progress)}% (${state.downloadedFiles}/${state.totalFiles})`;
        } else {
            containers.forEach(c => c?.classList.add('hidden'));
            if (drawerStatus) drawerStatus.innerText = "All materials available offline";
        }
    });
}

function startManualSync() {
    syncService.syncAllMaterials();
}



// Assignments Logic
function renderAssignments() {
    const assignments = JSON.parse(localStorage.getItem('assignments') || '[]');
    const container = document.getElementById('assignments-list');

    if (assignments.length === 0) {
        container.innerHTML = `
            <div class="text-center py-20">
                <i class="fa-solid fa-list-check text-6xl text-gray-200 mb-4"></i>
                <p class="text-gray-500">No assignments tracked yet.</p>
            </div>
        `;
        return;
    }

    container.innerHTML = assignments.map((task, index) => `
        <div class="bg-white dark:bg-darkCard p-5 rounded-3xl shadow-sm border border-gray-100 dark:border-gray-800 flex items-center group">
            <button onclick="toggleAssignment(${index})" class="w-6 h-6 rounded-full border-2 ${task.completed ? 'bg-primary border-primary text-white' : 'border-gray-300'} flex items-center justify-center mr-4">
                ${task.completed ? '<i class="fa-solid fa-check text-xs"></i>' : ''}
            </button>
            <div class="flex-1">
                <h4 class="font-bold ${task.completed ? 'line-through text-gray-400' : ''}">${task.title}</h4>
                <p class="text-xs text-gray-500">${task.course} • Due ${task.date}</p>
            </div>
            <button onclick="deleteAssignment(${index})" class="opacity-0 group-hover:opacity-100 text-red-500 p-2"><i class="fa-solid fa-trash"></i></button>
        </div>
    `).join('');
}

function showAddAssignmentModal() {
    const select = document.getElementById('assign-course');
    select.innerHTML = COURSE_DATA.map(c => `<option value="${c.title}">${c.title}</option>`).join('');
    document.getElementById('assignment-modal').classList.remove('hidden');
}

function hideAddAssignmentModal() {
    document.getElementById('assignment-modal').classList.add('hidden');
}

document.getElementById('assignment-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const title = document.getElementById('assign-title').value;
    const course = document.getElementById('assign-course').value;
    const date = document.getElementById('assign-date').value;

    const assignments = JSON.parse(localStorage.getItem('assignments') || '[]');
    assignments.push({ title, course, date, completed: false });
    localStorage.setItem('assignments', JSON.stringify(assignments));

    hideAddAssignmentModal();
    renderAssignments();
});

function toggleAssignment(index) {
    const assignments = JSON.parse(localStorage.getItem('assignments') || '[]');
    assignments[index].completed = !assignments[index].completed;
    localStorage.setItem('assignments', JSON.stringify(assignments));
    renderAssignments();
}

function deleteAssignment(index) {
    const assignments = JSON.parse(localStorage.getItem('assignments') || '[]');
    assignments.splice(index, 1);
    localStorage.setItem('assignments', JSON.stringify(assignments));
    renderAssignments();
}

// Mobile Menu
function toggleMobileMenu() {
    const drawer = document.getElementById('mobile-drawer');
    const content = document.getElementById('drawer-content');
    if (!drawer || !content) return;

    const isHidden = drawer.classList.contains('opacity-0');

    if (isHidden) {
        drawer.classList.remove('opacity-0', 'pointer-events-none');
        content.style.transform = 'translateX(0)';
    } else {
        drawer.classList.add('opacity-0', 'pointer-events-none');
        content.style.transform = 'translateX(-120%)';
    }
}

function hideMobileMenu() {
    const drawer = document.getElementById('mobile-drawer');
    const content = document.getElementById('drawer-content');
    if (!drawer || !content) return;
    drawer.classList.add('opacity-0', 'pointer-events-none');
    content.style.transform = 'translateX(-120%)';
}

// Storage Management
async function showStorageManager() {
    const size = await getOfflineCacheSize();
    document.getElementById('storage-usage').innerText = `${size} MB`;
    document.getElementById('storage-modal').classList.remove('hidden');
}

function hideStorageManager() {
    document.getElementById('storage-modal').classList.add('hidden');
}

async function clearOfflineCache() {
    await clearAllOfflineData();
    hideStorageManager();
    localStorage.removeItem('initial_sync_complete');
    alert("Cache cleared successfully!");
    location.reload();
}

function toggleLockIn() {
    isLockInEnabled = !isLockInEnabled;
    const btn = document.getElementById('lock-in-btn');
    const icon = btn.querySelector('i');

    if (isLockInEnabled) {
        icon.className = 'fa-solid fa-lock';
        btn.querySelector('.icon-box').classList.add('bg-accent/20');
        btn.querySelector('.icon-box').classList.add('text-primary');
        document.body.classList.add('lock-in-mode');

        // Visual Feedback
        const originalText = btn.querySelector('span').innerText;
        btn.querySelector('span').innerText = 'Locked In';

        // Wake Lock
        if ('wakeLock' in navigator) {
            navigator.wakeLock.request('screen').then(lock => {
                window.screenLock = lock;
            }).catch(err => console.error(err));
        }

        // Play alert sound if available
        const audio = new Audio('https://hcqaseovlciadogewnsw.supabase.co/storage/v1/object/public/materials/assets/notification_sound.mp3');
        audio.play().catch(() => {});

    } else {
        icon.className = 'fa-solid fa-lock-open';
        btn.querySelector('.icon-box').classList.remove('bg-accent/20');
        btn.querySelector('span').innerText = 'Lock-in';
        document.body.classList.remove('lock-in-mode');

        if (window.screenLock) {
            window.screenLock.release();
            window.screenLock = null;
        }
    }
}

function togglePasswordVisibility() {
    const input = document.getElementById('login-password');
    const icon = document.getElementById('password-toggle-icon');
    if (input.type === 'password') {
        input.type = 'text';
        icon.className = 'fa-solid fa-eye text-sm';
    } else {
        input.type = 'password';
        icon.className = 'fa-solid fa-eye-slash text-sm';
    }
}

// End of Logic

function logout() {
    if (confirm("Are you sure you want to logout?")) {
        localStorage.removeItem('readr_user');
        location.reload();
    }
}
