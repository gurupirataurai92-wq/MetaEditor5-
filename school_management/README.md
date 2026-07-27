# School Management System

A web-based school management system built with **Flask** and **SQLite**. It
provides role-based access for administrators, teachers, and students, and
covers the core operations a small school needs: managing students, teachers,
and courses; enrolling students; recording daily attendance; and keeping a
gradebook.

## Features

- **Authentication & roles** — session login with three roles:
  - **Admin** — full control: create/edit/delete students, teachers, and
    courses; assign teachers; enroll and drop students.
  - **Teacher** — view rosters, take attendance, and enter grades for the
    courses they teach.
  - **Student** — view their own profile, enrolled courses, scores, and grades.
- **Students** — CRUD, search by name, per-student profile with enrollments.
- **Teachers** — CRUD, department/contact details, courses taught.
- **Courses** — CRUD, teacher assignment, credits, roster.
- **Enrollment** — enroll/drop students, unique per student+course.
- **Attendance** — per-course, per-day roll with present/absent/late/excused.
- **Gradebook** — numeric scores (0–100) with automatically derived letter
  grades (A/B/C/D/F).

## Tech stack

| Layer     | Choice                          |
|-----------|---------------------------------|
| Backend   | Flask (application factory)     |
| ORM       | Flask-SQLAlchemy                |
| Auth      | Flask-Login, hashed passwords   |
| Database  | SQLite (configurable via env)   |
| Frontend  | Server-rendered Jinja2 + CSS    |

## Project layout

```
school_management/
├── app/
│   ├── __init__.py          # app factory, blueprints, error handlers
│   ├── models.py            # User, Teacher, Student, Course, Enrollment, Attendance
│   ├── routes/              # auth, main, students, teachers, courses, attendance, grades
│   ├── templates/           # Jinja2 templates
│   └── static/style.css     # styling
├── config.py                # configuration (env-overridable)
├── run.py                   # entrypoint
├── seed.py                  # demo data + logins
└── requirements.txt
```

## Getting started

```bash
cd school_management

# 1. Create a virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 2. Seed demo data (creates school.db)
python seed.py

# 3. Run the app
python run.py
```

Then open http://127.0.0.1:5000/.

## Demo logins

| Username | Password  | Role    |
|----------|-----------|---------|
| `admin`  | `admin123`| Admin   |
| `jsmith` | `teach123`| Teacher |
| `bwong`  | `teach123`| Teacher |
| `alice`  | `stud123` | Student |

> Change these before deploying anywhere real. Set a strong `SECRET_KEY`
> environment variable in production.

## Configuration

Override defaults with environment variables:

- `SECRET_KEY` — Flask session signing key.
- `DATABASE_URL` — SQLAlchemy database URI (defaults to a local SQLite file).
