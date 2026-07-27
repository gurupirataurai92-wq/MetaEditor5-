from flask import Blueprint, abort, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from app import db
from app.models import Course
from app.routes import roles_required

grades_bp = Blueprint("grades", __name__, url_prefix="/grades")


def _teacher_owns(course):
    if current_user.is_admin:
        return True
    return (
        current_user.is_teacher
        and current_user.teacher
        and course.teacher_id == current_user.teacher.id
    )


def _letter_for(score):
    """Derive a letter grade from a 0-100 score."""
    if score is None:
        return None
    if score >= 90:
        return "A"
    if score >= 80:
        return "B"
    if score >= 70:
        return "C"
    if score >= 60:
        return "D"
    return "F"


@grades_bp.route("/course/<int:course_id>", methods=["GET", "POST"])
@login_required
@roles_required("admin", "teacher")
def gradebook(course_id):
    course = db.get_or_404(Course, course_id)
    if not _teacher_owns(course):
        abort(403)

    if request.method == "POST":
        for enrollment in course.enrollments:
            raw = request.form.get(f"score_{enrollment.id}", "").strip()
            if raw == "":
                enrollment.score = None
                enrollment.grade = None
                continue
            try:
                score = max(0.0, min(100.0, float(raw)))
            except ValueError:
                flash(f"Invalid score for {enrollment.student.full_name}.", "danger")
                continue
            enrollment.score = score
            enrollment.grade = _letter_for(score)
        db.session.commit()
        flash("Grades saved.", "success")
        return redirect(url_for("grades.gradebook", course_id=course.id))

    return render_template("grades/gradebook.html", course=course)
