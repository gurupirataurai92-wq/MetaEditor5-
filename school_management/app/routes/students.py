from datetime import datetime

from flask import (
    Blueprint,
    abort,
    flash,
    redirect,
    render_template,
    request,
    url_for,
)
from flask_login import current_user, login_required

from app import db
from app.models import ROLE_STUDENT, Course, Enrollment, Student, User
from app.routes import roles_required

students_bp = Blueprint("students", __name__, url_prefix="/students")


def _parse_date(value):
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


@students_bp.route("/")
@login_required
@roles_required("admin", "teacher")
def index():
    search = request.args.get("q", "").strip()
    query = Student.query
    if search:
        like = f"%{search}%"
        query = query.filter(
            db.or_(Student.first_name.ilike(like), Student.last_name.ilike(like))
        )
    students = query.order_by(Student.last_name, Student.first_name).all()
    return render_template("students/index.html", students=students, search=search)


@students_bp.route("/<int:student_id>")
@login_required
def detail(student_id):
    student = db.get_or_404(Student, student_id)
    # Students may only view their own record.
    if current_user.is_student and current_user.student.id != student.id:
        abort(403)
    all_courses = Course.query.order_by(Course.code).all() if current_user.is_admin else []
    return render_template(
        "students/detail.html", student=student, all_courses=all_courses
    )


@students_bp.route("/new", methods=["GET", "POST"])
@login_required
@roles_required("admin")
def create():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        email = request.form.get("email", "").strip()
        password = request.form.get("password", "")

        error = None
        if not (username and email and password):
            error = "Username, email and password are required."
        elif User.query.filter_by(username=username).first():
            error = "That username is already taken."
        elif User.query.filter_by(email=email).first():
            error = "That email is already registered."

        if error:
            flash(error, "danger")
            return render_template("students/form.html", student=None, form=request.form)

        user = User(username=username, email=email, role=ROLE_STUDENT)
        user.set_password(password)
        student = Student(
            user=user,
            first_name=request.form.get("first_name", "").strip(),
            last_name=request.form.get("last_name", "").strip(),
            grade_level=request.form.get("grade_level", "").strip(),
            date_of_birth=_parse_date(request.form.get("date_of_birth")),
            guardian_name=request.form.get("guardian_name", "").strip(),
            phone=request.form.get("phone", "").strip(),
        )
        db.session.add(user)
        db.session.add(student)
        db.session.commit()
        flash(f"Student {student.full_name} created.", "success")
        return redirect(url_for("students.detail", student_id=student.id))

    return render_template("students/form.html", student=None, form={})


@students_bp.route("/<int:student_id>/edit", methods=["GET", "POST"])
@login_required
@roles_required("admin")
def edit(student_id):
    student = db.get_or_404(Student, student_id)
    if request.method == "POST":
        student.first_name = request.form.get("first_name", "").strip()
        student.last_name = request.form.get("last_name", "").strip()
        student.grade_level = request.form.get("grade_level", "").strip()
        student.date_of_birth = _parse_date(request.form.get("date_of_birth"))
        student.guardian_name = request.form.get("guardian_name", "").strip()
        student.phone = request.form.get("phone", "").strip()
        db.session.commit()
        flash("Student updated.", "success")
        return redirect(url_for("students.detail", student_id=student.id))

    return render_template("students/form.html", student=student, form={})


@students_bp.route("/<int:student_id>/delete", methods=["POST"])
@login_required
@roles_required("admin")
def delete(student_id):
    student = db.get_or_404(Student, student_id)
    user = student.user
    db.session.delete(student)
    if user:
        db.session.delete(user)
    db.session.commit()
    flash("Student deleted.", "info")
    return redirect(url_for("students.index"))


@students_bp.route("/<int:student_id>/enroll", methods=["POST"])
@login_required
@roles_required("admin")
def enroll(student_id):
    student = db.get_or_404(Student, student_id)
    course_id = request.form.get("course_id", type=int)
    course = db.session.get(Course, course_id) if course_id else None
    if not course:
        flash("Please choose a valid course.", "danger")
    elif Enrollment.query.filter_by(student_id=student.id, course_id=course.id).first():
        flash(f"{student.full_name} is already enrolled in {course.code}.", "warning")
    else:
        db.session.add(Enrollment(student_id=student.id, course_id=course.id))
        db.session.commit()
        flash(f"Enrolled in {course.code}.", "success")
    return redirect(url_for("students.detail", student_id=student.id))


@students_bp.route("/enrollments/<int:enrollment_id>/drop", methods=["POST"])
@login_required
@roles_required("admin")
def drop(enrollment_id):
    enrollment = db.get_or_404(Enrollment, enrollment_id)
    student_id = enrollment.student_id
    db.session.delete(enrollment)
    db.session.commit()
    flash("Enrollment removed.", "info")
    return redirect(url_for("students.detail", student_id=student_id))
