"""Seed the database with a demo admin, teachers, students, and courses.

Run with:  python seed.py
This is idempotent-ish: it wipes existing data and recreates the demo set.
"""

from datetime import date

from app import create_app, db
from app.models import (
    ROLE_ADMIN,
    ROLE_STUDENT,
    ROLE_TEACHER,
    Attendance,
    Course,
    Enrollment,
    Student,
    Teacher,
    User,
)


def make_user(username, email, role, password):
    user = User(username=username, email=email, role=role)
    user.set_password(password)
    db.session.add(user)
    return user


def run():
    app = create_app()
    with app.app_context():
        db.drop_all()
        db.create_all()

        # Admin
        make_user("admin", "admin@school.test", ROLE_ADMIN, "admin123")

        # Teachers
        t1_user = make_user("jsmith", "jsmith@school.test", ROLE_TEACHER, "teach123")
        t1 = Teacher(user=t1_user, first_name="Jane", last_name="Smith",
                     department="Mathematics", phone="555-0101")
        t2_user = make_user("bwong", "bwong@school.test", ROLE_TEACHER, "teach123")
        t2 = Teacher(user=t2_user, first_name="Brian", last_name="Wong",
                     department="Science", phone="555-0102")
        db.session.add_all([t1, t2])

        # Courses
        c1 = Course(code="MATH101", name="Algebra I", credits=3,
                    description="Introduction to algebra.", teacher=t1)
        c2 = Course(code="MATH201", name="Geometry", credits=3,
                    description="Plane and solid geometry.", teacher=t1)
        c3 = Course(code="SCI101", name="Biology", credits=4,
                    description="Foundations of biology.", teacher=t2)
        db.session.add_all([c1, c2, c3])

        # Students
        students = []
        demo = [
            ("Alice", "Johnson", "Grade 9", "alice", "Mary Johnson"),
            ("Marco", "Rossi", "Grade 9", "marco", "Luca Rossi"),
            ("Priya", "Patel", "Grade 10", "priya", "Anil Patel"),
            ("Diego", "Garcia", "Grade 10", "diego", "Sofia Garcia"),
        ]
        for first, last, grade, uname, guardian in demo:
            u = make_user(uname, f"{uname}@school.test", ROLE_STUDENT, "stud123")
            s = Student(user=u, first_name=first, last_name=last,
                        grade_level=grade, guardian_name=guardian,
                        date_of_birth=date(2010, 1, 1))
            db.session.add(s)
            students.append(s)

        db.session.flush()  # assign ids

        # Enrollments with some grades
        enrollments = [
            Enrollment(student=students[0], course=c1, score=92, grade="A"),
            Enrollment(student=students[0], course=c3, score=85, grade="B"),
            Enrollment(student=students[1], course=c1, score=78, grade="C"),
            Enrollment(student=students[2], course=c2, score=88, grade="B"),
            Enrollment(student=students[2], course=c3, score=95, grade="A"),
            Enrollment(student=students[3], course=c2),
        ]
        db.session.add_all(enrollments)

        # A day of attendance for MATH101
        db.session.add_all([
            Attendance(student=students[0], course=c1, on_date=date.today(), status="present"),
            Attendance(student=students[1], course=c1, on_date=date.today(), status="late"),
        ])

        db.session.commit()

        print("Seed complete. Demo logins (username / password):")
        print("  admin   / admin123   (administrator)")
        print("  jsmith  / teach123   (teacher)")
        print("  bwong   / teach123   (teacher)")
        print("  alice   / stud123    (student)")


if __name__ == "__main__":
    run()
