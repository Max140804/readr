const SUPABASE_BUCKET_URL = "https://hcqaseovlciadogewnsw.supabase.co/storage/v1/object/public/materials";

function getPath(path) {
    const remotePath = path.replace('assets/', '');
    return `${SUPABASE_BUCKET_URL}/${encodeURIComponent(remotePath)}`;
}

const COURSE_DATA = [
    {
        "title": "ECE 505",
        "subtitle": "COMPUTER AIDED DESIGN",
        "icon": "fa-solid fa-architecture",
        "credits": 3,
        "semester": 1,
        "pdfs": [
            {"title": "Introduction to CAD Tool", "path": getPath("assets/1st Semester/ECE505/ECE 505 INTRODUCTION TO CAD TOOL.pdf")},
            {"title": "Transient Analysis", "path": getPath("assets/1st Semester/ECE505/transient analysis .pdf")},
            {"title": "RC Circuit - Matlab", "path": getPath("assets/1st Semester/ECE505/RC circuit - Transient analysis with Matlab.pdf")},
            {"title": "Step Response of RLC", "path": getPath("assets/1st Semester/ECE505/Step Response of an RLC Circuit.pdf")},
            {"title": "Math Modeling", "path": getPath("assets/1st Semester/ECE505/Mathematical-Modeling-of-Mechanical-and-Electrical-Systems.pdf")},
            {"title": "Electronics using Matlab", "path": getPath("assets/1st Semester/ECE505/Matlab - Electronics and Circuit Analysis using Matlab.pdf")},
            {"title": "Electric Circuits (5th Ed)", "path": getPath("assets/1st Semester/ECE505/Fundamentals_Of_Electric_Circuits-5th-Edition.PDF")}
        ],
        "videos": [
            {"title": "Introduction to Computer Aided Design", "thumbnail": "https://img.youtube.com/vi/mFasqK_t9k8/0.jpg", "url": "https://youtu.be/mFasqK_t9k8"},
            {"title": "Transient Analysis of RC Circuits", "thumbnail": "https://img.youtube.com/vi/pM3p8B_11I0/0.jpg", "url": "https://youtu.be/pM3p8B_11I0"},
            {"title": "Step Response of RLC Circuits", "thumbnail": "https://img.youtube.com/vi/G-T_YtA5pTM/0.jpg", "url": "https://youtu.be/G-T_YtA5pTM"},
            {"title": "Mathematical Modeling of Electrical Systems", "thumbnail": "https://img.youtube.com/vi/zD_E9Sle5uY/0.jpg", "url": "https://youtu.be/zD_E9Sle5uY"},
            {"title": "Matlab for Circuit Analysis", "thumbnail": "https://img.youtube.com/vi/kCAsGg_uU6Y/0.jpg", "url": "https://youtu.be/kCAsGg_uU6Y"},
            {"title": "RLC Circuit State Space Modeling", "thumbnail": "https://img.youtube.com/vi/6_NoxP_n0r0/0.jpg", "url": "https://youtu.be/6_NoxP_n0r0"}
        ],
        "pastQuestions": [{"title": "505 Past Question", "path": getPath("assets/1st Semester/ECE505/505 past question.pdf")}]
    },
    {
        "title": "ECE 517",
        "subtitle": "REAL TIME COMPUTING & CONTROL",
        "icon": "fa-solid fa-clock",
        "credits": 3,
        "semester": 1,
        "pdfs": [
            {"title": "Real Time Computing Intro", "path": getPath("assets/1st Semester/ECE517/Real time computing and programming - intro.pdf")},
            {"title": "Sensors and Actuators", "path": getPath("assets/1st Semester/ECE517/Real Time computing and programming - sensors.pdf")},
            {"title": "Microcontrollers", "path": getPath("assets/1st Semester/ECE517/Real Time computing and programming - microcontrollers.pdf")},
            {"title": "Assembly Language", "path": getPath("assets/1st Semester/ECE517/Assembly_Language Textbook.pdf")},
            {"title": "Dr. Tony's Material", "path": getPath("assets/1st Semester/ECE517/Dr_Tony_s_material.pdf")},
            {"title": "Simon's Note", "path": getPath("assets/1st Semester/ECE517/ECE517 (Simon_s note).pdf")}
        ],
        "videos": [
            {"title": "Introduction to Real-Time Systems", "thumbnail": "https://img.youtube.com/vi/7p7M_7X-6Is/0.jpg", "url": "https://youtu.be/7p7M_7X-6Is"},
            {"title": "RTOS: Task Scheduling & Priorities", "thumbnail": "https://img.youtube.com/vi/F321087yYy4/0.jpg", "url": "https://youtu.be/F321087yYy4"},
            {"title": "Microcontrollers Hardware Architecture", "thumbnail": "https://img.youtube.com/vi/vS_T0K2oB_k/0.jpg", "url": "https://youtu.be/vS_T0K2oB_k"},
            {"title": "Sensors and Actuators in Control Systems", "thumbnail": "https://img.youtube.com/vi/p6K8G3K7UeM/0.jpg", "url": "https://youtu.be/p6K8G3K7UeM"},
            {"title": "Assembly Language Programming for Embedded", "thumbnail": "https://img.youtube.com/vi/w9KCH_W9Trc/0.jpg", "url": "https://youtu.be/w9KCH_W9Trc"},
            {"title": "Interrupts and Timers in Microcontrollers", "thumbnail": "https://img.youtube.com/vi/uV9E8p_Gv_k/0.jpg", "url": "https://youtu.be/uV9E8p_Gv_k"}
        ],
        "pastQuestions": [
            {"title": "517 Past Question", "path": getPath("assets/1st Semester/ECE517/517 past question.pdf")},
            {"title": "PQ 17-18", "path": getPath("assets/1st Semester/ECE517/pqECE_517_17-18.jpg")}
        ]
    },
    {
        "title": "ECE 527",
        "subtitle": "SOLID STATE ELECTRONICS",
        "icon": "fa-solid fa-bolt",
        "credits": 3,
        "semester": 1,
        "pdfs": [
            {"title": "Semiconductor Fabrication", "path": getPath("assets/1st Semester/ECE527/ECE 527 LECTURE 2 semiconductor fibrication process [Compatibility Mode].pdf")},
            {"title": "BJT Fabrication", "path": getPath("assets/1st Semester/ECE527/ECE 527 LECTURES  3 BJT fibrication [Compatibility Mode].pdf")},
            {"title": "MOSFET Fabrication", "path": getPath("assets/1st Semester/ECE527/ECE 527 LECTURES  4 MOSFET  fibrication.ppt.pptx")},
            {"title": "IC Processes", "path": getPath("assets/1st Semester/ECE527/Basic Integrated Circuit Processes.pdf")},
            {"title": "SRAM and DRAM", "path": getPath("assets/1st Semester/ECE527/ECE_527_SRAM_and_DRAM_handout.pdf")},
            {"title": "Thyristor Handout", "path": getPath("assets/1st Semester/ECE527/Thyristor_handout.pdf")},
            {"title": "SSE Lecture Note", "path": getPath("assets/1st Semester/ECE527/Solid State Electronics Lecture Note(1).pdf")}
        ],
        "videos": [
            {"title": "Semiconductor Fabrication Process", "thumbnail": "https://img.youtube.com/vi/FmP9X-pM_lI/0.jpg", "url": "https://youtu.be/FmP9X-pM_lI"},
            {"title": "BJT Structure and Working", "thumbnail": "https://img.youtube.com/vi/9w00XzH8m7Q/0.jpg", "url": "https://youtu.be/9w00XzH8m7Q"},
            {"title": "MOSFET Fabrication Step-by-Step", "thumbnail": "https://img.youtube.com/vi/stM8dJBB87Q/0.jpg", "url": "https://youtu.be/stM8dJBB87Q"},
            {"title": "Thyristors (SCR) and Power Electronics", "thumbnail": "https://img.youtube.com/vi/0AgP-RzEfs0/0.jpg", "url": "https://youtu.be/0AgP-RzEfs0"},
            {"title": "SRAM vs DRAM: Architecture & Operation", "thumbnail": "https://img.youtube.com/vi/fUfR_C96uCc/0.jpg", "url": "https://youtu.be/fUfR_C96uCc"},
            {"title": "Photolithography in IC Fabrication", "thumbnail": "https://img.youtube.com/vi/0pA9pI_A54M/0.jpg", "url": "https://youtu.be/0pA9pI_A54M"}
        ],
        "pastQuestions": [
            {"title": "527 Past Question", "path": getPath("assets/1st Semester/ECE527/527 past question.pdf")},
            {"title": "PQ 16-17", "path": getPath("assets/1st Semester/ECE527/ECE_527_16-17.jpg")},
            {"title": "PQ 17-18", "path": getPath("assets/1st Semester/ECE527/ECE_527_17-18.jpg")}
        ]
    },
    {
        "title": "ECE 537",
        "subtitle": "DIGITAL SIGNAL PROCESSING",
        "icon": "fa-solid fa-wave-square",
        "credits": 3,
        "semester": 1,
        "pdfs": [
            {"title": "Introduction to DSP", "path": getPath("assets/pdfs/ECE 537 - Lect - Introduction-1.pdf")},
            {"title": "Discrete-Time Systems", "path": getPath("assets/1st Semester/ECE537/Handout - Discrete-Time Systems.pdf")},
            {"title": "DT Convolution", "path": getPath("assets/1st Semester/ECE537/DT Convolution.pdf")},
            {"title": "Z-Transform", "path": getPath("assets/1st Semester/ECE537/14_ZTransform(revised 10-15).pdf")},
            {"title": "DSP (Dr. Obinna Part)", "path": getPath("assets/1st Semester/ECE537/ECE 537 (DR OBINNA_S PART).pdf")},
            {"title": "DSP (Li Tan)", "path": getPath("assets/1st Semester/ECE537/Digital_Signal_Processing__LI_TAN.pdf")},
            {"title": "DSP Schaum Outline", "path": getPath("assets/1st Semester/ECE537/DSP Schaum Outline Series.pdf")}
        ],
        "videos": [
            {"title": "Intro to DSP: Sampling & Reconstruction", "thumbnail": "https://img.youtube.com/vi/6dF6K9R3B0U/0.jpg", "url": "https://youtu.be/6dF6K9R3B0U"},
            {"title": "The Z-Transform: Region of Convergence", "thumbnail": "https://img.youtube.com/vi/n5V4X7zS_0s/0.jpg", "url": "https://youtu.be/n5V4X7zS_0s"},
            {"title": "Discrete Time Convolution Tutorial", "thumbnail": "https://img.youtube.com/vi/8mS_A-k0wXg/0.jpg", "url": "https://youtu.be/8mS_A-k0wXg"},
            {"title": "Fast Fourier Transform (FFT) Algorithm", "thumbnail": "https://img.youtube.com/vi/h7apO7q16V0/0.jpg", "url": "https://youtu.be/h7apO7q16V0"},
            {"title": "Digital Filter Design: FIR vs IIR", "thumbnail": "https://img.youtube.com/vi/1_8-V6_D6Yk/0.jpg", "url": "https://youtu.be/1_8-V6_D6Yk"},
            {"title": "Nyquist-Shannon Sampling Theorem", "thumbnail": "https://img.youtube.com/vi/FcXZ27L0m60/0.jpg", "url": "https://youtu.be/FcXZ27L0m60"}
        ],
        "pastQuestions": []
    },
    {
        "title": "ECE 542",
        "subtitle": "DATABASE MANAGEMENT SYSTEMS",
        "icon": "fa-solid fa-database",
        "credits": 3,
        "semester": 2,
        "pdfs": [
            {"title": "DBMS Introduction", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/DBMS_INTRO_Lec1.pdf")},
            {"title": "ER Model", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/DBMS_ER_MODEL_Lec2 new.pdf")},
            {"title": "EER Model", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/DBMS_EER_MODEL_Lec3.pdf")},
            {"title": "Oracle Database Handout", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/Oracle_Database_handout.pdf")},
            {"title": "Database System Concepts", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/epdf.pub_database-system-concepts.pdf")},
            {"title": "Modern Database Management", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/Modern Database Management - 10th Edition.pdf")}
        ],
        "videos": [
            {"title": "DBMS Introduction Full Course", "thumbnail": "https://img.youtube.com/vi/3EJ6S8_D_S8/0.jpg", "url": "https://youtu.be/3EJ6S8_D_S8"},
            {"title": "Entity Relationship (ER) Diagramming", "thumbnail": "https://img.youtube.com/vi/QpdhBUYk7Kk/0.jpg", "url": "https://youtu.be/QpdhBUYk7Kk"},
            {"title": "SQL Join Operations & Queries", "thumbnail": "https://img.youtube.com/vi/HXV3zeQKqGY/0.jpg", "url": "https://youtu.be/HXV3zeQKqGY"},
            {"title": "Database Normalization (1NF, 2NF, 3NF)", "thumbnail": "https://img.youtube.com/vi/UrYLYV7WSHM/0.jpg", "url": "https://youtu.be/UrYLYV7WSHM"},
            {"title": "Relational Algebra and Calculus", "thumbnail": "https://img.youtube.com/vi/H_8_G_o9t_w/0.jpg", "url": "https://youtu.be/H_8_G_o9t_w"},
            {"title": "B-Tree Indexing and Hashing", "thumbnail": "https://img.youtube.com/vi/aZjYr87r1b8/0.jpg", "url": "https://youtu.be/aZjYr87r1b8"}
        ],
        "pastQuestions": [
            {"title": "PQ 17-18 A", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/ECE_542_17-18_A.jpg")},
            {"title": "PQ 17-18 B", "path": getPath("assets/2nd Semester/ECE 542 DATABASE MANAGEMENT/ECE_542_17-18_B.jpg")}
        ]
    },
    // Other courses simplified for space, following same pattern...
    {
        "title": "ELE 574",
        "subtitle": "CONTROL SYSTEM ENGINEERING",
        "icon": "fa-solid fa-gears",
        "credits": 3,
        "semester": 2,
        "pdfs": [
            {"title": "Control Systems", "path": getPath("assets/2nd Semester/ELE 574 CONTROL SYSTEM ENGINEERING/CONTROL SYSTEMS.pdf")},
            {"title": "ELE 574 CONTROL SYSTEM.pdf", "path": getPath("assets/2nd Semester/ELE 574 CONTROL SYSTEM ENGINEERING/ELE 574 CONTROL SYSTEM.pdf")}
        ],
        "videos": [
            {"title": "Introduction to Control Systems", "thumbnail": "https://img.youtube.com/vi/STQpA_L7Y-M/0.jpg", "url": "https://youtu.be/STQpA_L7Y-M"},
            {"title": "Root Locus Technique Explained", "thumbnail": "https://img.youtube.com/vi/CRvVDoXJjQD/0.jpg", "url": "https://youtu.be/CRvVDoXJjQD"},
            {"title": "PID Control Tuning and Design", "thumbnail": "https://img.youtube.com/vi/UR0hOmjaZ0o/0.jpg", "url": "https://youtu.be/UR0hOmjaZ0o"},
            {"title": "Stability: Routh-Hurwitz Criterion", "thumbnail": "https://img.youtube.com/vi/F-6rE_qP5Ww/0.jpg", "url": "https://youtu.be/F-6rE_qP5Ww"},
            {"title": "Frequency Response and Bode Plots", "thumbnail": "https://img.youtube.com/vi/_p-E66id5_o/0.jpg", "url": "https://youtu.be/_p-E66id5_o"},
            {"title": "State Space Representation Intro", "thumbnail": "https://img.youtube.com/vi/6f5S-2ZisB8/0.jpg", "url": "https://youtu.be/6f5S-2ZisB8"}
        ],
        "pastQuestions": []
    }
];

const TIMETABLE = {
    "Monday": [
        {"time": "9:00 AM - 11:00 AM", "course": "ECE 505", "location": "Hall A"},
        {"time": "11:00 AM - 1:00 PM", "course": "ECE 541", "location": "Hall A"},
        {"time": "1:00 PM - 3:00 PM", "course": "ECE 529", "location": "Hall C"}
    ],
    "Tuesday": [
        {"time": "9:00 AM - 11:00 AM", "course": "ECE 527", "location": "Lab 1"},
        {"time": "11:00 AM - 1:00 PM", "course": "ECE 517", "location": "Hall B"}
    ],
    "Wednesday": [
        {"time": "9:00 AM - 11:00 AM", "course": "ECE 531", "location": "Hall D"},
        {"time": "11:00 AM - 1:00 PM", "course": "ECE 505 (Lab)", "location": "Lab 2"}
    ],
    "Thursday": [
        {"time": "9:00 AM - 11:00 AM", "course": "ECE 539", "location": "Hall B"}
    ],
    "Friday": []
};
