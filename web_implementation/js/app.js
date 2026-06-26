// Supabase Initialization
const SUPABASE_URL = 'https://hcqaseovlciadogewnsw.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhjcWFzZW92bGNpYWRvZ2V3bnN3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDczMjYsImV4cCI6MjA5NTI4MzMyNn0.HUeREBkAYeZYyv9ekq5a0kVuhpAgFTJJzydzau8Zrdk';
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// State Management
let currentPage = 'home';
let isDarkMode = localStorage.getItem('theme') === 'dark' || (window.matchMedia('(prefers-color-scheme: dark)').matches && !localStorage.getItem('theme'));
let currentMaterials = [];
let currentPdf = null;

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
        const avatar = document.querySelector('.w-8.h-8.bg-primary.rounded-full');
        if (avatar) avatar.innerText = user.name[0];
        const drawerAvatar = document.querySelector('.w-16.h-16.bg-white.rounded-2xl');
        if (drawerAvatar) drawerAvatar.innerText = user.name[0];
    }
}

function showLoginPage() {
    document.getElementById('login-modal').classList.remove('hidden');
    document.getElementById('login-modal').classList.add('flex');
}

async function handleLogin(e) {
    e.preventDefault();
    const regno = document.getElementById('login-regno').value;
    const surname = document.getElementById('login-surname').value;
    const password = document.getElementById('login-password').value;

    if (!regno || !surname || !password) return;

    // Simulate login / save to local storage
    const user = {
        name: surname,
        regno: regno,
        id: 'user_' + Date.now()
    };
    localStorage.setItem('readr_user', JSON.stringify(user));

    document.getElementById('login-modal').classList.add('hidden');
    document.getElementById('login-modal').classList.remove('flex');

    document.getElementById('user-name').innerText = surname;

    location.reload(); // Refresh to ensure all components pick up user data
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

    if (pageId === 'assistant') loadChat();
    if (pageId === 'forum') loadForum();
    if (pageId === 'bookmarks') renderBookmarks();
    if (pageId === 'assignments') renderAssignments();
    if (pageId === 'courses') renderAllCourses();
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
            <div class="w-10 h-10 rounded-xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center text-primary dark:text-blue-400 mb-4">
                <i class="${course.icon}"></i>
            </div>
            <h4 class="font-bold text-lg">${course.title}</h4>
            <p class="text-xs text-gray-500 dark:text-gray-400 mb-4 line-clamp-1">${course.subtitle}</p>
            <div class="flex items-center text-[10px] font-bold text-gray-400 mb-4">
                <i class="fa-solid fa-bookmark mr-1 text-accent"></i>
                ${course.credits} CREDIT UNITS
            </div>
            <div class="mt-auto">
                <button class="w-full py-2 bg-blue-50 dark:bg-blue-900/20 text-primary dark:text-blue-400 rounded-xl font-bold text-sm">View</button>
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
            <div class="space-y-4">
                <h3 class="text-xl font-bold flex items-center">
                    <span class="w-2 h-8 bg-primary rounded-full mr-3"></span>
                    ${day}
                </h3>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    ${slots.length > 0 ? slots.map(slot => `
                        <div class="bg-white dark:bg-darkCard p-5 rounded-[2.5rem] shadow-sm border border-gray-100 dark:border-gray-800 flex items-center">
                            <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center text-primary mr-4">
                                <i class="fa-solid fa-clock"></i>
                            </div>
                            <div>
                                <h4 class="font-bold">${slot.course}</h4>
                                <p class="text-xs text-gray-500">${slot.time} • ${slot.location}</p>
                            </div>
                        </div>
                    `).join('') : '<p class="text-gray-400 text-sm ml-5">No lectures scheduled</p>'}
                </div>
            </div>
        `;
    }).join('');
}

// Chat Assistant Logic
const GROQ_API_KEY = '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';

async function getAIResponse(query) {
    try {
        const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${GROQ_API_KEY}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model: "llama-3.1-70b-versatile",
                messages: [
                    { role: "system", content: "You are Readr AI, a helpful academic assistant for ECE students at UNIZIK. Use the provided course context to help students." },
                    { role: "user", content: query }
                ],
                temperature: 0.7
            })
        });
        const data = await response.json();
        return data.choices[0].message.content;
    } catch (e) {
        console.error("AI Error:", e);
        return "Sorry, I'm having trouble connecting to my brain. Please try again later.";
    }
}

function loadChat() {
    const messages = JSON.parse(localStorage.getItem('chat_history') || '[]');
    const container = document.getElementById('chat-messages');

    if (messages.length > 0) {
        container.innerHTML = messages.map(msg => `
            <div class="chat-bubble ${msg.role === 'user' ? 'user' : 'bot'}">
                ${msg.text}
            </div>
        `).join('');
    }

    container.scrollTop = container.scrollHeight;
}

document.getElementById('chat-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const input = document.getElementById('chat-input');
    const text = input.value.trim();
    if (!text) return;

    appendMessage('user', text);
    input.value = '';

    // Show typing indicator
    const typingId = 'typing-' + Date.now();
    const container = document.getElementById('chat-messages');
    const typingDiv = document.createElement('div');
    typingDiv.id = typingId;
    typingDiv.className = 'chat-bubble bot italic text-gray-400';
    typingDiv.innerText = 'Thinking...';
    container.appendChild(typingDiv);
    container.scrollTop = container.scrollHeight;

    const response = await getAIResponse(text);

    document.getElementById(typingId)?.remove();
    appendMessage('bot', response);
});

function appendMessage(role, text) {
    const container = document.getElementById('chat-messages');
    const div = document.createElement('div');
    div.className = `chat-bubble ${role}`;
    div.innerText = text;
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;

    const history = JSON.parse(localStorage.getItem('chat_history') || '[]');
    history.push({ role, text });
    if (history.length > 50) history.shift(); // Keep history manageable
    localStorage.setItem('chat_history', JSON.stringify(history));
}

function clearChat() {
    if (confirm("Clear chat history?")) {
        localStorage.removeItem('chat_history');
        document.getElementById('chat-messages').innerHTML = `
            <div class="chat-bubble bot">Hello! I'm your Readr Assistant. How can I help you with your studies today?</div>
        `;
    }
}

// Forum Logic
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
    supabaseClient.channel('public:forum_posts')
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'forum_posts' }, payload => {
            appendForumMessage(payload.new, true);
        })
        .subscribe();

    const { data: posts, error } = await supabaseClient
        .from('forum_posts')
        .select('*')
        .order('created_at', { ascending: true });

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
    const isMe = user && post.username === user.name;
    const time = post.created_at ? new Date(post.created_at).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : 'Just now';
    return `
        <div class="flex space-x-4 ${isMe ? 'flex-row-reverse space-x-reverse' : ''}">
            <div class="w-10 h-10 ${isMe ? 'bg-primary' : 'bg-gray-400'} rounded-full flex items-center justify-center text-white font-bold flex-shrink-0 uppercase">
                ${(post.username || 'A')[0]}
            </div>
            <div class="flex-1">
                <div class="${isMe ? 'bg-primary/10 border-primary/20' : 'bg-gray-100 dark:bg-gray-800'} p-4 rounded-2xl ${isMe ? 'rounded-tr-none' : 'rounded-tl-none'} border">
                    <p class="font-bold text-xs mb-1 ${isMe ? 'text-primary' : ''}">${post.username || 'Anonymous'}</p>
                    <p class="text-sm">${post.message}</p>
                </div>
                <p class="text-[10px] text-gray-400 mt-1 ${isMe ? 'text-right mr-2' : 'ml-2'}">${time}</p>
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
        .from('forum_posts')
        .insert([{
            message: text,
            username: user.name,
            user_id: user.id,
            created_at: new Date().toISOString()
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
    container.appendChild(div);
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
}

function renderBookmarks() {
    const bookmarks = JSON.parse(localStorage.getItem('bookmarks') || '[]');
    const container = document.getElementById('bookmarks-list');

    if (bookmarks.length === 0) {
        container.innerHTML = `
            <div class="text-center py-20">
                <i class="fa-solid fa-bookmark text-6xl text-gray-200 mb-4"></i>
                <p class="text-gray-500">No saved materials yet.</p>
            </div>
        `;
        return;
    }

    container.innerHTML = bookmarks.map(b => `
        <div class="bg-white dark:bg-darkCard p-4 rounded-3xl shadow-sm border border-gray-100 dark:border-gray-800 flex items-center justify-between">
            <div class="flex items-center cursor-pointer flex-1" onclick="openPdf('${b.path}', '${b.title}', 'Saved')">
                <div class="w-10 h-10 bg-accent/20 rounded-xl flex items-center justify-center text-primary mr-4">
                    <i class="fa-solid fa-file-pdf"></i>
                </div>
                <div>
                    <h5 class="font-bold text-sm">${b.title}</h5>
                    <p class="text-[10px] text-gray-400">Saved on ${b.date}</p>
                </div>
            </div>
            <button onclick="toggleBookmark('${b.path}', '${b.title}')" class="text-primary p-2">
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
    grid.innerHTML = sem1.map(course => `
        <div class="course-card" onclick="viewMaterials('${course.title}')">
            <div class="w-10 h-10 rounded-xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center text-primary dark:text-blue-400 mb-4">
                <i class="${course.icon}"></i>
            </div>
            <h4 class="font-bold text-lg">${course.title}</h4>
            <p class="text-xs text-gray-500 dark:text-gray-400 mb-4 line-clamp-1">${course.subtitle}</p>
            <div class="flex items-center text-[10px] font-bold text-gray-400 mb-4">
                <i class="fa-solid fa-bookmark mr-1 text-accent"></i>
                ${course.credits} CREDIT UNITS
            </div>
            <div class="mt-auto">
                <button class="w-full py-2 bg-blue-50 dark:bg-blue-900/20 text-primary dark:text-blue-400 rounded-xl font-bold text-sm">View</button>
            </div>
        </div>
    `).join('');
}

async function viewMaterials(courseTitle) {
    const course = COURSE_DATA.find(c => c.title === courseTitle);
    if (!course) return;

    document.getElementById('materials-title').innerText = `${course.title} Materials`;
    const listContainer = document.getElementById('materials-list');

    let html = '';

    // Lecture Materials Section
    if (course.pdfs && course.pdfs.length > 0) {
        html += `<h3 class="text-sm font-bold text-gray-400 uppercase tracking-widest mb-4">Lecture Materials</h3>`;
        const pdfsHtml = await Promise.all(course.pdfs.map(async (pdf) => {
            const isCached = await isFileOffline(pdf.path);
            return renderMaterialItem(pdf, isCached, course.title);
        }));
        html += pdfsHtml.join('');
    }

    // Past Questions Section
    if (course.pastQuestions && course.pastQuestions.length > 0) {
        html += `<h3 class="text-sm font-bold text-gray-400 uppercase tracking-widest mt-8 mb-4">Past Questions</h3>`;
        const pqHtml = await Promise.all(course.pastQuestions.map(async (pq) => {
            const isCached = await isFileOffline(pq.path);
            return renderMaterialItem(pq, isCached, course.title, 'fa-solid fa-paste text-blue-500');
        }));
        html += pqHtml.join('');
    }

    // Videos Section
    if (course.videos && course.videos.length > 0) {
        html += `<h3 class="text-sm font-bold text-gray-400 uppercase tracking-widest mt-8 mb-4">Video Lessons</h3>`;
        const videosHtml = course.videos.map(video => `
            <div class="bg-white dark:bg-darkCard p-4 rounded-3xl shadow-sm border border-gray-100 dark:border-gray-800 flex items-center cursor-pointer hover:border-primary transition-colors mb-4" onclick="openVideoPlayer('${video.url}', '${video.title}')">
                <div class="w-16 h-12 bg-gray-100 dark:bg-gray-800 rounded-xl overflow-hidden mr-4 relative">
                    <img src="${video.thumbnail}" class="w-full h-full object-cover opacity-80">
                    <div class="absolute inset-0 flex items-center justify-center">
                        <i class="fa-solid fa-play text-white text-xs"></i>
                    </div>
                </div>
                <div class="flex-1 min-w-0">
                    <h5 class="font-bold truncate">${video.title}</h5>
                    <span class="text-[10px] text-gray-400 font-bold">In-app player</span>
                </div>
                <i class="fa-solid fa-play text-primary text-xs"></i>
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
        <div class="bg-white dark:bg-darkCard p-4 rounded-3xl shadow-sm border border-gray-100 dark:border-gray-800 flex items-center cursor-pointer hover:border-primary transition-colors mb-4" onclick="openPdf('${item.path}', '${item.title}', '${courseTitle}')">
            <div class="w-12 h-12 bg-gray-50 dark:bg-gray-800 rounded-2xl flex items-center justify-center mr-4">
                <i class="${iconClass} text-xl"></i>
            </div>
            <div class="flex-1 min-w-0">
                <h5 class="font-bold truncate">${item.title}</h5>
                <div class="flex items-center mt-1">
                    ${isCached ?
                        `<span class="text-[10px] text-green-500 font-bold flex items-center"><i class="fa-solid fa-circle-check mr-1"></i> Available Offline</span>` :
                        `<span class="text-[10px] text-gray-400 font-bold">Tap to ${isImage ? 'view' : 'open'}</span>`
                    }
                </div>
            </div>
            <i class="fa-solid fa-chevron-right text-gray-300 text-sm"></i>
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
        if (offlineFile) {
            const url = URL.createObjectURL(offlineFile.blob);
            iframe.src = url;
        } else {
            iframe.src = path;
            // Cache it for future offline use
            fetch(path)
                .then(res => res.blob())
                .then(blob => {
                    saveFileOffline(path, title, blob);
                    // Refresh view to show checkmark if still on materials page
                    if (document.getElementById('materials-page').classList.contains('active')) {
                        viewMaterials(courseName);
                    }
                })
                .catch(err => console.error("Auto-cache failed:", err));
        }
    } catch (e) {
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

// Alarms Logic
function renderAlarms() {
    const alarms = JSON.parse(localStorage.getItem('alarms') || '[]');
    const container = document.getElementById('alarms-list');

    if (alarms.length === 0) {
        container.innerHTML = `
            <div class="text-center py-20">
                <i class="fa-solid fa-clock text-6xl text-gray-200 mb-4"></i>
                <p class="text-gray-500">No alarms set.</p>
            </div>
        `;
        return;
    }

    container.innerHTML = alarms.map((alarm, index) => `
        <div class="bg-white dark:bg-darkCard p-6 rounded-[2.5rem] shadow-sm border border-gray-100 dark:border-gray-800 flex items-center justify-between">
            <div class="flex items-center">
                <div class="w-14 h-14 bg-primary/10 rounded-2xl flex items-center justify-center text-primary mr-5">
                    <i class="fa-solid fa-bell text-2xl"></i>
                </div>
                <div>
                    <h4 class="text-2xl font-black">${alarm.time}</h4>
                    <p class="text-sm text-gray-500">${alarm.label}</p>
                </div>
            </div>
            <div class="flex items-center space-x-4">
                <label class="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" ${alarm.enabled ? 'checked' : ''} onchange="toggleAlarm(${index})" class="sr-only peer">
                    <div class="w-11 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-primary"></div>
                </label>
                <button onclick="deleteAlarm(${index})" class="text-red-500 p-2"><i class="fa-solid fa-trash"></i></button>
            </div>
        </div>
    `).join('');
}

function showAddAlarmModal() {
    document.getElementById('alarm-modal').classList.remove('hidden');
}

function hideAddAlarmModal() {
    document.getElementById('alarm-modal').classList.add('hidden');
}

document.getElementById('alarm-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const label = document.getElementById('alarm-label').value;
    const time = document.getElementById('alarm-time').value;

    const alarms = JSON.parse(localStorage.getItem('alarms') || '[]');
    alarms.push({ label, time, enabled: true });
    localStorage.setItem('alarms', JSON.stringify(alarms));

    if ("Notification" in window) {
        Notification.requestPermission();
    }

    hideAddAlarmModal();
    renderAlarms();
});

function toggleAlarm(index) {
    const alarms = JSON.parse(localStorage.getItem('alarms') || '[]');
    alarms[index].enabled = !alarms[index].enabled;
    localStorage.setItem('alarms', JSON.stringify(alarms));
}

function deleteAlarm(index) {
    if (confirm("Delete this alarm?")) {
        const alarms = JSON.parse(localStorage.getItem('alarms') || '[]');
        alarms.splice(index, 1);
        localStorage.setItem('alarms', JSON.stringify(alarms));
        renderAlarms();
    }
}

// Background alarm checker
setInterval(() => {
    const alarms = JSON.parse(localStorage.getItem('alarms') || '[]');
    const now = new Date();
    const currentTime = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;

    alarms.forEach(alarm => {
        if (alarm.enabled && alarm.time === currentTime && now.getSeconds() === 0) {
            playAlarm(alarm);
        }
    });
}, 1000);

function playAlarm(alarm) {
    if ("Notification" in window && Notification.permission === "granted") {
        new Notification("Study Time!", {
            body: `It's time for: ${alarm.label}`,
            icon: "../assets/logo.png"
        });
    }

    // Play sound if possible
    const audio = new Audio('https://hcqaseovlciadogewnsw.supabase.co/storage/v1/object/public/materials/assets/notification_sound.mp3');
    audio.play().catch(e => console.log("Audio play blocked"));

    alert(`ALARM: ${alarm.label}`);
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
    drawer.classList.toggle('opacity-0');
    drawer.classList.toggle('pointer-events-none');
    content.classList.toggle('translate-x-[-100%]');
}

function hideMobileMenu() {
    const drawer = document.getElementById('mobile-drawer');
    const content = document.getElementById('drawer-content');
    drawer.classList.add('opacity-0');
    drawer.classList.add('pointer-events-none');
    content.classList.add('translate-x-[-100%]');
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

// End of Logic

function logout() {
    if (confirm("Are you sure you want to logout?")) {
        localStorage.removeItem('readr_user');
        location.reload();
    }
}
