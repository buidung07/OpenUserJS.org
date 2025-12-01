// ==UserScript==
// @name        HDANG
// @author       Trần Bảo Ngọc & Gemini
// @description  Khoanh xanh cả Ô Kéo và Ô Thả - Hỗ trợ bài Nối cực mạnh
// @namespace    http://tampermonkey.net/
// @match        *://*.wayground.com/*
// @match        *://*.quizizz.com/*
// @grant        GM_xmlhttpRequest
// @grant        unsafeWindow
// @run-at       document-end
// @version      0.1.6.ConnectFix
// ==/UserScript==
(function() {
    'use strict';

    // === CẤU HÌNH ===
    let CONFIG = {
        autoClick: false,    // Mặc định TẮT (Bạn tự kéo)
        minDelay: 2000,
        maxDelay: 5000
    };

    let cachedAnswers = new Set(); // Dùng Set để tra cứu cực nhanh
    let lastQ = '';
    let isWaitingClick = false;
    let uiRefs = { input: null, btn: null, status: null, dot: null, toggle: null };
    let isMenuOpen = false;

    // === TIỆN ÍCH ===
    const normalize = (text) => {
        if (!text) return '';
        return text.toString()
            .replace(/<[^>]*>/g, '') // Xóa HTML
            .replace(/&nbsp;/g, ' ')
            .toLowerCase()
            .replace(/\s+/g, ' ')    // Xóa khoảng trắng thừa
            .trim();
    };

    const random = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;

    // 1. TÌM PIN
    function findPin() {
        const href = window.location.href;
        let m = href.match(/[?&]gc=(\d+)/) || href.match(/[?&]pin=(\d+)/) || href.match(/join\/(\d+)/);
        if (m) return m[1];
        try {
            const body = document.body.innerText;
            const pins = body.match(/(?<!\d)(\d{3,4}\s?\d{3,4})(?!\d)/g);
            if (pins) {
                for (let p of pins) {
                    let cleanP = p.replace(/\s/g, '');
                    if (cleanP.length >= 6 && cleanP.length <= 8) return cleanP;
                }
            }
        } catch (e) {}
        return null;
    }

    // 2. TẢI ĐÁP ÁN
    async function fetchAnswers(pin) {
        const { btn, status, dot } = uiRefs;

        if(dot) dot.style.background = "#facc15";
        if(status) { status.innerText = `⏳ ${pin}...`; status.style.color = "#facc15"; }

        try {
            const res = await fetch(`https://api.quizit.online/quizizz/answers?pin=${pin}`);
            const json = await res.json();
            if (!json?.data?.answers) throw new Error("No Data");

            // Reset cache
            cachedAnswers.clear();

            json.data.answers.forEach(i => {
                // Với mỗi câu hỏi, ta lưu TẤT CẢ các thành phần của đáp án vào Set
                // Ví dụ: Câu nối "Mèo" -> "Meow". Ta lưu cả "mèo" và "meow" vào cache.
                if (Array.isArray(i.answers)) {
                    i.answers.forEach(ans => {
                        cachedAnswers.add(normalize(ans.text));
                        // Nếu đáp án có dạng match (Quizizz cũ):
                        if (ans.match) cachedAnswers.add(normalize(ans.match));
                    });
                } else {
                    cachedAnswers.add(normalize(i.answers?.[0]?.text));
                }
            });

            if(dot) { dot.style.background = "#4ade80"; dot.style.boxShadow = "0 0 10px #4ade80"; }
            if(status) status.innerHTML = `<span style="color:#4ade80">✅ Đã học: ${json.data.answers.length} câu</span>`;
            if(btn) { btn.innerText = "READY"; btn.style.background = "#22c55e"; }

            return true;
        } catch (e) {
            if(dot) dot.style.background = "#ef4444";
            if(status) { status.innerText = "Lỗi"; status.style.color = "#ef4444"; }
            return false;
        }
    }

    // 3. XỬ LÝ (HIGHLIGHT CẢ 2 ĐẦU)
    function solve() {
        if (cachedAnswers.size === 0) return;

        // Tìm câu hỏi (để check xem câu hỏi đã đổi chưa)
        let qText = '';
        const qSelectors = ['.question-text-color', '[data-testid="question-container"]', '.question-container', 'h1', '.query-text'];
        for (let sel of qSelectors) {
            const el = document.querySelector(sel);
            if (el) { qText = normalize(el.innerText); if(qText.length>5) break; }
        }

        if (!qText) return;

        // === QUÉT MỞ RỘNG (Tìm cả ô thả) ===
        // Thêm các class .bucket, .drop-zone, .match-option, và cả div chứa text
        const candidates = document.querySelectorAll('.option, [role="button"], .answer-card, .option-text-inner, .bucket, .drop-zone, .match-option, .resizeable-gap, .dnd-drop-zone, .dnd-draggable, div[draggable="true"], div[class*="content"]');

        let foundCorrectOption = null;

        candidates.forEach(opt => {
            // Bỏ qua các thẻ quá to chứa nhiều thứ linh tinh
            if (opt.childElementCount > 3 && !opt.classList.contains('option')) return;

            const optText = normalize(opt.innerText);
            if (!optText || optText.length < 1) return;

            // KIỂM TRA: Text của thẻ này có nằm trong danh sách đáp án đúng không?
            // Dùng Set.has để check cực nhanh
            let isCorrect = false;

            if (cachedAnswers.has(optText)) {
                isCorrect = true;
            } else {
                // Check dự phòng: nếu text trong nút dài và chứa đáp án (hoặc ngược lại)
                // (Chỉ áp dụng với text dài > 3 ký tự để tránh nhầm số)
                if (optText.length > 3) {
                    for (let ans of cachedAnswers) {
                        if (ans.length > 3 && (optText === ans || optText.includes(ans) || ans.includes(optText))) {
                             // Fix lỗi: Không highlight thẻ cha bao trùm thẻ con
                             if (optText.length < ans.length + 20) {
                                 isCorrect = true;
                                 break;
                             }
                        }
                    }
                }
            }

            // HIGHLIGHT
            if (isCorrect) {
                // Lưu lại 1 cái để auto click (nếu bật)
                if (!foundCorrectOption && !opt.classList.contains('highlighted-v16')) foundCorrectOption = opt;

                if (opt.style.borderColor !== 'rgb(0, 255, 0)') {
                    opt.style.border = "4px solid #00FF00";
                    opt.style.boxShadow = "inset 0 0 20px rgba(0, 255, 0, 0.5)"; // Sáng cả bên trong
                    opt.style.borderRadius = "8px";
                    opt.style.transition = "all 0.2s";
                    opt.style.zIndex = "100"; // Nổi lên trên cùng
                    opt.classList.add('highlighted-v16'); // Đánh dấu đã tô
                }
            } else {
                // Xóa highlight nếu sai (cập nhật realtime)
                if (opt.style.borderColor === 'rgb(0, 255, 0)') {
                    opt.style.border = "";
                    opt.style.boxShadow = "";
                    opt.classList.remove('highlighted-v16');
                }
            }
        });

        // AUTO CLICK LOGIC
        if (CONFIG.autoClick && foundCorrectOption && qText !== lastQ && !isWaitingClick) {
            isWaitingClick = true;
            lastQ = qText;
            const delay = random(CONFIG.minDelay, CONFIG.maxDelay);
            let timeLeft = delay/1000;
            const timer = setInterval(() => {
                timeLeft -= 0.1;
                if(uiRefs.status) uiRefs.status.innerText = `🖱️ Click: ${timeLeft.toFixed(1)}s`;
                if(timeLeft <= 0) clearInterval(timer);
            }, 100);

            setTimeout(() => {
                foundCorrectOption.click();
                isWaitingClick = false;
                if(uiRefs.status) uiRefs.status.innerText = "✅ Done";
            }, delay);
        } else if (!CONFIG.autoClick && qText !== lastQ) {
            lastQ = qText;
            if(uiRefs.status) uiRefs.status.innerText = "👀 Đã tô xanh";
        }
    }

    // 4. UI (MINI LEFT)
    function makeDraggable(el, onClick) {
        let isDragging=false,sx,sy,il,it,hm=false;
        const start=(x,y)=>{isDragging=true;hm=false;sx=x;sy=y;let r=el.getBoundingClientRect();il=r.left;it=r.top;el.style.transition='none';};
        const move=(x,y)=>{if(!isDragging)return;if(Math.abs(x-sx)>5||Math.abs(y-sy)>5)hm=true;el.style.left=(il+x-sx)+'px';el.style.top=(it+y-sy)+'px';el.style.right='auto';};
        const end=()=>{if(isDragging){isDragging=false;el.style.transition='0.3s';if(!hm&&onClick)onClick();}};
        el.onmousedown=e=>{e.preventDefault();start(e.clientX,e.clientY)};window.onmousemove=e=>move(e.clientX,e.clientY);window.onmouseup=end;
        el.ontouchstart=e=>{start(e.touches[0].clientX,e.touches[0].clientY)};window.ontouchmove=e=>{if(isDragging)e.preventDefault();move(e.touches[0].clientX,e.touches[0].clientY)};window.ontouchend=end;
    }

    function renderUI() {
        if (document.getElementById('hack-root-v16')) return;
        const root = document.createElement('div'); root.id = 'hack-root-v16';
        const shadow = root.attachShadow({ mode: 'open' });

        const style = document.createElement('style');
        style.textContent = `
            .assist-btn { position: fixed; top: 60%; right: 10px; width: 45px; height: 45px; background: rgba(0,0,0,0.7); border-radius: 12px; border: 1px solid #666; cursor: pointer; z-index: 999999; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px); }
            .assist-circle { width: 14px; height: 14px; background: #fff; border-radius: 50%; transition: 0.3s; }
            .panel { position: fixed; bottom: 80px; left: 20px; width: 160px; padding: 12px; background: rgba(10, 10, 15, 0.95); border-radius: 12px; border: 1px solid #444; color: white; font-family: sans-serif; opacity: 0; pointer-events: none; transform: scale(0.8); transform-origin: bottom left; transition: 0.2s; z-index: 999998; box-shadow: 0 5px 20px rgba(0,0,0,0.5); }
            .panel.open { opacity: 1; pointer-events: auto; transform: scale(1); }
            input { width: 100%; padding: 8px; margin-bottom: 8px; background: #222; border: 1px solid #555; color: white; text-align: center; border-radius: 6px; font-size: 12px; box-sizing: border-box; }
            button { width: 100%; padding: 8px; background: #3b82f6; border: none; border-radius: 6px; color: white; font-weight: bold; font-size: 11px; cursor: pointer; margin-bottom: 8px; }
            .toggle-row { display: flex; align-items: center; justify-content: space-between; font-size: 11px; margin-top: 5px; color: #ccc; background: #222; padding: 5px; border-radius: 6px; }
            .toggle-switch { width: 34px; height: 18px; background: #444; border-radius: 10px; position: relative; cursor: pointer; transition: 0.3s; }
            .toggle-switch.on { background: #4ade80; }
            .toggle-circle { width: 14px; height: 14px; background: white; border-radius: 50%; position: absolute; top: 2px; left: 2px; transition: 0.3s; }
            .toggle-switch.on .toggle-circle { left: 18px; }
            .status { margin-top: 8px; font-size: 10px; text-align: center; color: #888; font-weight: bold; }
        `;

        const btn = document.createElement('div'); btn.className = 'assist-btn'; btn.innerHTML = '<div class="assist-circle" id="dot"></div>';
        const panel = document.createElement('div'); panel.className = 'panel';
        panel.innerHTML = `
            <div style="text-align:center;font-size:10px;color:#4ade80;margin-bottom:5px">V16: CONNECT FIX</div>
            <input type="text" id="pin" placeholder="PIN Game">
            <button id="go">LOAD DATA</button>
            <div class="toggle-row">
                <span>Auto Click</span>
                <div class="toggle-switch" id="toggle"><div class="toggle-circle"></div></div>
            </div>
            <div class="status" id="st">Chờ PIN...</div>
        `;

        shadow.appendChild(style); shadow.appendChild(btn); shadow.appendChild(panel);
        document.documentElement.appendChild(root);

        uiRefs.input = shadow.getElementById('pin'); uiRefs.btn = shadow.getElementById('go');
        uiRefs.status = shadow.getElementById('st'); uiRefs.dot = shadow.getElementById('dot');
        uiRefs.toggle = shadow.getElementById('toggle');

        makeDraggable(btn, () => { isMenuOpen = !isMenuOpen; panel.className = isMenuOpen ? 'panel open' : 'panel'; });
        document.addEventListener('click', e => { if(isMenuOpen && e.target !== root) { isMenuOpen = false; panel.className = 'panel'; }});
        panel.onclick = e => e.stopPropagation();

        uiRefs.btn.onclick = () => { const p = uiRefs.input.value.trim(); if(p) fetchAnswers(p); };
        uiRefs.toggle.onclick = () => { CONFIG.autoClick = !CONFIG.autoClick; uiRefs.toggle.className = CONFIG.autoClick ? 'toggle-switch on' : 'toggle-switch'; uiRefs.status.innerText = CONFIG.autoClick ? "Auto ON" : "Auto OFF"; };

        setInterval(() => {
            const p = findPin();
            if(p && !cachedAnswers.size && uiRefs.input.value !== p) { uiRefs.input.value = p; fetchAnswers(p); }
            solve();
        }, 500);
    }

    renderUI();
})();
