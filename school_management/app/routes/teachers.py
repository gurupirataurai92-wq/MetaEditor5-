from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import login_required

from app import db
from app.models import ROLE_TEACHER, Teacher, User
from app.routes import roles_required

teachers_bp = Blueprint("teachers", __name__, url_prefix="/teachers")


@teachers_bp.route("/")
@login_required
@roles_required("admin", "teacher")
def index():
    teachers = Teacher.query.order_by(Teacher.last_name, Teacher.first_name).all()
    return render_template("teachers/index.html", teachers=teachers)


@teachers_bp.route("/<int:teacher_id>")
@login_required
@roles_required("admin", "teacher")
def detail(teacher_id):
    teacher = db.get_or_404(Teacher, teacher_id)
    return render_template("teachers/detail.html", teacher=teacher)


@teachers_bp.route("/new", methods=["GET", "POST"])
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
            return render_template("teachers/form.html", teacher=None, form=request.form)

        user = User(username=username, email=email, role=ROLE_TEACHER)
        user.set_password(password)
        teacher = Teacher(
            user=user,
            first_name=request.form.get("first_name", "").strip(),
            last_name=request.form.get("last_name", "").strip(),
            department=request.form.get("department", "").strip(),
            phone=request.form.get("phone", "").strip(),
        )
        db.session.add(user)
        db.session.add(teacher)
        db.session.commit()
        flash(f"Teacher {teacher.full_name} created.", "success")
        return redirect(url_for("teachers.detail", teacher_id=teacher.id))

    return render_template("teachers/form.html", teacher=None, form={})


@teachers_bp.route("/<int:teacher_id>/edit", methods=["GET", "POST"])
@login_required
@roles_required("admin")
def edit(teacher_id):
    teacher = db.get_or_404(Teacher, teacher_id)
    if request.method == "POST":
        teacher.first_name = request.form.get("first_name", "").strip()
        teacher.last_name = request.form.get("last_name", "").strip()
        teacher.department = request.form.get("department", "").strip()
        teacher.phone = request.form.get("phone", "").strip()
        db.session.commit()
        flash("Teacher updated.", "success")
        return redirect(url_for("teachers.detail", teacher_id=teacher.id))

    return render_template("teachers/form.html", teacher=teacher, form={})


@teachers_bp.route("/<int:teacher_id>/delete", methods=["POST"])
@login_required
@roles_required("admin")
def delete(teacher_id):
    teacher = db.get_or_404(Teacher, teacher_id)
    # Detach from any courses so the course rows survive.
    for course in teacher.courses:
        course.teacher_id = None
    user = teacher.user
    db.session.delete(teacher)
    if user:
        db.session.delete(user)
    db.session.commit()
    flash("Teacher deleted.", "info")
    return redirect(url_for("teachers.index"))
