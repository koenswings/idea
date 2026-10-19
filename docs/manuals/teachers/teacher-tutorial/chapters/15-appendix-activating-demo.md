**Status:** Authoritative · **Maintained by:** Marco (with Atlas) · 19 October 2026 (demo setup = separate Demo apps)

# Appendix: activating the demo setup

The demo setup puts example data on an IDEA box for training. It is always a **separate app**, never added inside the school's own Kolibri or Nextcloud: **Kolibri Demo** and **Nextcloud Demo**. On the kit, both are already installed on every IDEA box, with the demo content.

**What it creates in Kolibri Demo:**

- the school **IDEA Demo School**
- the class **Grade 5**
- the admin account `admin`, the teachers `teacher1` and `teacher2` (coaches of Grade 5) and the learners `learner1` to `learner3`. Learners have no password: they sign in with only their username.
- the three channels of the IDEA-DEMO disk.

**What it creates in Nextcloud Demo:** the groups `teachers` and `learners`, the accounts `admin`, `teacher1`, `teacher2` and `learner1` to `learner3`, and the folders `Worksheets` and `Teacher Notes` for both teachers.

The accounts are listed in *Appendix: demo accounts*. Lessons are not created: the teacher makes them, as in chapter 3.

**Who sets it up.** Your IDEA contact. It is not a button in the Console. It is a script that comes with each app (`demo/install-demo.sh` in the Kolibri app and in the Nextcloud app). It installs the Demo app if it is missing, or fills the existing one again.

The script can be run again safely. It makes no second Demo app, deletes nothing and keeps passwords that were already changed.
