// Mumixic Website Interactive Logic
document.addEventListener("DOMContentLoaded", () => {
  // 1. Subtle interactive 3D perspective tilt on phone mockups
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

  // 2. Subtle mouse reactive glow tracking
  const glow1 = document.querySelector(".glow-1");
  window.addEventListener("mousemove", (e) => {
    if (glow1) {
      const moveX = (e.clientX - window.innerWidth / 2) * 0.04;
      const moveY = (e.clientY - window.innerHeight / 2) * 0.04;
      glow1.style.transform = `translate(${moveX}px, ${moveY}px)`;
    }
  });
});
