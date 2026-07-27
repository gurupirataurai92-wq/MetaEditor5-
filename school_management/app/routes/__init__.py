from functools import wraps

from flask import abort
from flask_login import current_user


def roles_required(*roles):
    """Restrict a view to users whose role is in *roles.

    Assumes the view is already protected by @login_required.
    """

    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not current_user.is_authenticated or current_user.role not in roles:
                abort(403)
            return view(*args, **kwargs)

        return wrapped

    return decorator
