/* ═══════════════════════════════════════════════════════════
   SafeSwap — Interactive Elements
   ═══════════════════════════════════════════════════════════ */

(function () {
    'use strict';

    // ── Hero Shield Grid ──
    function initHeroGrid() {
        const canvas = document.createElement('canvas');
        const container = document.getElementById('hero-grid');
        if (!container) return;

        container.appendChild(canvas);
        const ctx = canvas.getContext('2d');

        let w, h, cols, rows, nodes = [];
        const spacing = 60;
        const accentRGB = { r: 0, g: 212, b: 170 };

        function resize() {
            w = canvas.width = container.offsetWidth;
            h = canvas.height = container.offsetHeight;
            cols = Math.ceil(w / spacing) + 1;
            rows = Math.ceil(h / spacing) + 1;
            nodes = [];

            for (let r = 0; r < rows; r++) {
                for (let c = 0; c < cols; c++) {
                    nodes.push({
                        x: c * spacing,
                        y: r * spacing,
                        baseAlpha: 0.08 + Math.random() * 0.06,
                        alpha: 0,
                        pulse: Math.random() * Math.PI * 2,
                        speed: 0.3 + Math.random() * 0.5
                    });
                }
            }
        }

        let mouseX = -1000, mouseY = -1000;
        container.addEventListener('mousemove', (e) => {
            const rect = container.getBoundingClientRect();
            mouseX = e.clientX - rect.left;
            mouseY = e.clientY - rect.top;
        });
        container.addEventListener('mouseleave', () => {
            mouseX = -1000;
            mouseY = -1000;
        });

        let time = 0;
        function draw() {
            ctx.clearRect(0, 0, w, h);
            time += 0.016;

            for (const node of nodes) {
                const dx = mouseX - node.x;
                const dy = mouseY - node.y;
                const dist = Math.sqrt(dx * dx + dy * dy);
                const proximity = Math.max(0, 1 - dist / 200);
                const pulse = Math.sin(time * node.speed + node.pulse) * 0.3 + 0.7;

                node.alpha = node.baseAlpha * pulse + proximity * 0.35;

                // Draw node
                ctx.beginPath();
                ctx.arc(node.x, node.y, 1.5 + proximity * 2, 0, Math.PI * 2);
                ctx.fillStyle = `rgba(${accentRGB.r}, ${accentRGB.g}, ${accentRGB.b}, ${node.alpha})`;
                ctx.fill();

                // Draw connections to nearby nodes
                if (proximity > 0.05) {
                    for (const other of nodes) {
                        const ox = other.x - node.x;
                        const oy = other.y - node.y;
                        const odist = Math.sqrt(ox * ox + oy * oy);
                        if (odist > 0 && odist <= spacing * 1.5) {
                            ctx.beginPath();
                            ctx.moveTo(node.x, node.y);
                            ctx.lineTo(other.x, other.y);
                            ctx.strokeStyle = `rgba(${accentRGB.r}, ${accentRGB.g}, ${accentRGB.b}, ${proximity * 0.12})`;
                            ctx.lineWidth = 0.5;
                            ctx.stroke();
                        }
                    }
                }
            }

            requestAnimationFrame(draw);
        }

        resize();
        draw();
        window.addEventListener('resize', resize);
    }

    // ── Scroll Reveals ──
    function initScrollReveals() {
        const elements = document.querySelectorAll('[data-reveal]');
        if (!elements.length) return;

        const observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    if (entry.isIntersecting) {
                        entry.target.classList.add('revealed');
                        observer.unobserve(entry.target);
                    }
                });
            },
            { threshold: 0.12, rootMargin: '0px 0px -40px 0px' }
        );

        elements.forEach((el) => observer.observe(el));
    }

    // ── Nav Scroll State ──
    function initNav() {
        const nav = document.getElementById('nav');
        if (!nav) return;

        let ticking = false;
        window.addEventListener('scroll', () => {
            if (!ticking) {
                requestAnimationFrame(() => {
                    nav.classList.toggle('nav--scrolled', window.scrollY > 40);
                    ticking = false;
                });
                ticking = true;
            }
        });
    }

    // ── Mobile Menu ──
    function initMobileMenu() {
        const toggle = document.querySelector('.nav__toggle');
        const menu = document.getElementById('mobile-menu');
        if (!toggle || !menu) return;

        toggle.addEventListener('click', () => {
            menu.classList.toggle('active');
            document.body.style.overflow = menu.classList.contains('active') ? 'hidden' : '';
        });

        menu.querySelectorAll('a').forEach((link) => {
            link.addEventListener('click', () => {
                menu.classList.remove('active');
                document.body.style.overflow = '';
            });
        });
    }

    // ── Smooth Scroll for Anchor Links ──
    function initSmoothScroll() {
        document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
            anchor.addEventListener('click', (e) => {
                const target = document.querySelector(anchor.getAttribute('href'));
                if (target) {
                    e.preventDefault();
                    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }
            });
        });
    }

    // ── Init ──
    document.addEventListener('DOMContentLoaded', () => {
        initHeroGrid();
        initScrollReveals();
        initNav();
        initMobileMenu();
        initSmoothScroll();
    });
})();
