**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 16 October 2026

# Appendix: activating the demo setup

The demo setup fills Kolibri on an IDEA box with example data. It is for demo IDEA boxes and training only. Do not use it on a school's real IDEA box: it adds **IDEA Demo School** and makes it the main Kolibri school on that box.

**What it creates in Kolibri:**

- the school **IDEA Demo School**
- the class **Grade 5**
- the admin account `admin`, the teacher `teacher1` (coach of Grade 5) and the learners `learner1` to `learner3`

The accounts are listed in *Appendix: demo accounts*. Lessons are not created: the teacher makes them, as in chapter 3.

**Who turns it on.** Your IDEA contact. It is not a button in the Console. It is a script that comes with the Kolibri app (`demo/provision-demo.sh` in the Kolibri app).

**How it works:**

1. The IDEA contact stops Kolibri on the IDEA box.
2. They run the demo script once, on the Kolibri app's data.
3. They start Kolibri again.
4. Kolibri now has IDEA Demo School, Grade 5 and the demo accounts.

You can run the script again safely. It deletes nothing and keeps passwords that were already changed.

**Channels.** The Maths, Grade 5 Science and Early Reading channels come from the **IDEA-DEMO** disk, through the channel builder (chapter 5).
