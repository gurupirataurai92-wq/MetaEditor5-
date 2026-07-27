from flask import Blueprint, redirect, render_template, url_for
from flask_login import current_user, login_required

from app.models import Course, Enrollment, Student, Teacher

main_bp = Blueprint("main", __name__)


@main_bp.route("/")
def index():
    if current_user.is_authenticated:
        return redirect(url_for("main.dashboard"))
    return redirect(url_for("auth.login"))


@main_bp.route("/dashboard")
@login_required
def dashboard():
    stats = {
        "students": Student.query.count(),
        "teachers": Teacher.query.count(),
        "courses": Course.query.count(),
        "enrollments": Enrollment.query.count(),
    }

    context = {"stats": stats}

    if current_user.is_teacher and current_user.teacher:
        context["my_courses"] = current_user.teacher.courses
    elif current_user.is_student and current_user.student:
        context["my_enrollments"] = current_user.student.enrollments

    return render_template("dashboard.html", **context)
