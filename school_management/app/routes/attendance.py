from datetime import date, datetime

from flask import Blueprint, abort, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from app import db
from app.models import Attendance, Course
from app.routes import roles_required

attendance_bp = Blueprint("attendance", __name__, url_prefix="/attendance")

VALID_STATUSES = {"present", "absent", "late", "excused"}


def _teacher_owns(course):
    """Admins manage any course; teachers only their own."""
    if current_user.is_admin:
        return True
    return (
        current_user.is_teacher
        and current_user.teacher
        and course.teacher_id == current_user.teacher.id
    )


@attendance_bp.route("/course/<int:course_id>", methods=["GET", "POST"])
@login_required
@roles_required("admin", "teacher")
def take(course_id):
    course = db.get_or_404(Course, course_id)
    if not _teacher_owns(course):
        abort(403)

    on_date = request.values.get("date")
    try:
        on_date = datetime.strptime(on_date, "%Y-%m-%d").date() if on_date else date.today()
    except ValueError:
        on_date = date.today()

    if request.method == "POST":
        for enrollment in course.enrollments:
            status = request.form.get(f"status_{enrollment.student_id}", "present")
            if status not in VALID_STATUSES:
                status = "present"
            record = Attendance.query.filter_by(
                student_id=enrollment.student_id,
                course_id=course.id,
                on_date=on_date,
            ).first()
            if record:
                record.status = status
            else:
                db.session.add(
                    Attendance(
                        student_id=enrollment.student_id,
                        course_id=course.id,
                        on_date=on_date,
                        status=status,
                    )
                )
        db.session.commit()
        flash(f"Attendance saved for {on_date.isoformat()}.", "success")
        return redirect(url_for("attendance.take", course_id=course.id, date=on_date.isoformat()))

    # Existing records for the chosen day, keyed by student id.
    existing = {
        r.student_id: r.status
        for r in Attendance.query.filter_by(course_id=course.id, on_date=on_date).all()
    }
    return render_template(
        "attendance/take.html", course=course, on_date=on_date, existing=existing
    )
