// Mumixic Website Interactive Logic
document.addEventListener("DOMContentLoaded", () => {
  // 1. Font Switcher: Apple Serif vs Helvetica
  const btnSerif = document.getElementById("btn-font-serif");
  const btnHelvetica = document.getElementById("btn-font-helvetica");
  const body = document.body;

  const savedFont = localStorage.getItem("mumixic-header-font") || "serif";
  applyFont(savedFont);

  if (btnSerif && btnHelvetica) {
    btnSerif.addEventListener("click", () => {
      applyFont("serif");
    });

    btnHelvetica.addEventListener("click", () => {
      applyFont("helvetica");
    });
  }

  function applyFont(type) {
    if (type === "helvetica") {
      body.classList.remove("font-serif-headers");
      body.classList.add("font-helvetica-headers");
      btnHelvetica?.classList.add("active");
      btnSerif?.classList.remove("active");
      localStorage.setItem("mumixic-header-font", "helvetica");
    } else {
      body.classList.remove("font-helvetica-headers");
      body.classList.add("font-serif-headers");
      btnSerif?.classList.add("active");
      btnHelvetica?.classList.remove("active");
      localStorage.setItem("mumixic-header-font", "serif");
    }
  }

  // 2. Subtle interactive 3D perspective tilt on mockups
  const cards = document.querySelectorAll(".device-card");
  cards.forEach(card => {
    card.addEventListener("mousemove", (e) => {
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;
      const tiltX = (y / (rect.height / 2)) * -6;
      const tiltY = (x / (rect.width / 2)) * 6;
      card.style.transform = `perspective(1000px) rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateY(-14px) scale(1.02)`;
    });

    card.addEventListener("mouseleave", () => {
      card.style.transform = "";
    });
  });

  // 3. Navbar backdrop scroll state
  const navbar = document.querySelector(".navbar");
  window.addEventListener("scroll", () => {
    if (window.scrollY > 40) {
      navbar.style.borderBottomColor = "rgba(255, 255, 255, 0.12)";
      navbar.style.background = "rgba(8, 7, 13, 0.88)";
    } else {
      navbar.style.borderBottomColor = "rgba(255, 255, 255, 0.08)";
      navbar.style.background = "rgba(8, 7, 13, 0.72)";
    }
  });

  // 4. Subtle mouse reactive glow tracking
  const glow1 = document.querySelector(".glow-1");
  window.addEventListener("mousemove", (e) => {
    if (glow1) {
      const moveX = (e.clientX - window.innerWidth / 2) * 0.04;
      const moveY = (e.clientY - window.innerHeight / 2) * 0.04;
      glow1.style.transform = `translate(${moveX}px, ${moveY}px)`;
    }
  });
});
