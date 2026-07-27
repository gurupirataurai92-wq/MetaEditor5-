from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from app import db
from app.models import Course, Teacher
from app.routes import roles_required

courses_bp = Blueprint("courses", __name__, url_prefix="/courses")


@courses_bp.route("/")
@login_required
def index():
    courses = Course.query.order_by(Course.code).all()
    return render_template("courses/index.html", courses=courses)


@courses_bp.route("/<int:course_id>")
@login_required
def detail(course_id):
    course = db.get_or_404(Course, course_id)
    return render_template("courses/detail.html", course=course)


@courses_bp.route("/new", methods=["GET", "POST"])
@login_required
@roles_required("admin")
def create():
    if request.method == "POST":
        code = request.form.get("code", "").strip().upper()
        error = None
        if not code or not request.form.get("name", "").strip():
            error = "Course code and name are required."
        elif Course.query.filter_by(code=code).first():
            error = f"Course code {code} already exists."

        if error:
            flash(error, "danger")
            return render_template(
                "courses/form.html",
                course=None,
                form=request.form,
                teachers=Teacher.query.all(),
            )

        course = Course(
            code=code,
            name=request.form.get("name", "").strip(),
            description=request.form.get("description", "").strip(),
            credits=request.form.get("credits", type=int) or 1,
            teacher_id=request.form.get("teacher_id", type=int) or None,
        )
        db.session.add(course)
        db.session.commit()
        flash(f"Course {course.code} created.", "success")
        return redirect(url_for("courses.detail", course_id=course.id))

    return render_template(
        "courses/form.html", course=None, form={}, teachers=Teacher.query.all()
    )


@courses_bp.route("/<int:course_id>/edit", methods=["GET", "POST"])
@login_required
@roles_required("admin")
def edit(course_id):
    course = db.get_or_404(Course, course_id)
    if request.method == "POST":
        course.name = request.form.get("name", "").strip()
        course.description = request.form.get("description", "").strip()
        course.credits = request.form.get("credits", type=int) or 1
        course.teacher_id = request.form.get("teacher_id", type=int) or None
        db.session.commit()
        flash("Course updated.", "success")
        return redirect(url_for("courses.detail", course_id=course.id))

    return render_template(
        "courses/form.html", course=course, form={}, teachers=Teacher.query.all()
    )


@courses_bp.route("/<int:course_id>/delete", methods=["POST"])
@login_required
@roles_required("admin")
def delete(course_id):
    course = db.get_or_404(Course, course_id)
    db.session.delete(course)
    db.session.commit()
    flash("Course deleted.", "info")
    return redirect(url_for("courses.index"))
