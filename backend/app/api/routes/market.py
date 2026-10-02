"""Market linkage, QR packages, and the mobile processing van.

Every route here mounts onto an EXISTING surface:

  /market/*  -> FPO Market Linkage + Buyer Procurement
  /qr/*      -> QR identity / clone detection, used by Consumer verification
                and by the processor / FPO that issued the label
  /van/*     -> KVIC Field Officer mobile processing van submodule

None of these introduces a new portal, and each one reuses the roles that
already exist. Authorization is enforced by `require_roles`, not by the UI.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from ...core.security import get_current_user, require_roles
from ...schemas import market as m

router = APIRouter(prefix="/api/v1", tags=["market"])

# Roles that may sell or buy. `institution` (KVIC) is read-only oversight and is
# deliberately absent from the write paths.
MARKET_ACTORS = ("fpo", "processor", "buyer", "admin")
LISTING_WRITERS = ("fpo", "processor", "admin")
# Anyone authenticated may scan a code — that is the consumer verification path —
# but only the issuing organization may issue or recall a label.
PACKAGE_WRITERS = ("fpo", "processor", "admin")
# The van is the KVIC field officer's submodule.
VAN_ROLES = ("institution", "admin")


def _fail(exc: Exception) -> HTTPException:
    """Map a domain rejection onto the right HTTP status.

    A value error is a client mistake (409 conflict for state violations, 400
    for malformed input); a permission error is 403. Neither is a 500.
    """
    if isinstance(exc, PermissionError):
        return HTTPException(status_code=403, detail=str(exc))
    message = str(exc)
    # A conflict is a valid request against a state that cannot satisfy it —
    # more kilograms requested than remain, an order already decided, a van not
    # yet on site. Anything else is malformed input (400).
    blocked = (
        "remain",
        "must move to",
        "already",
        "not open",
        "cannot be",
        "blocks listing",
        "only an accepted",
        "only a pending",
        "on site",
    )
    if any(token in message for token in blocked):
        return HTTPException(status_code=409, detail=message)
    return HTTPException(status_code=400, detail=message)


# ------------------------------------------------------------- market ------
@router.get("/market/listings", response_model=list[m.ListingRead])
def list_listings(
    request: Request,
    user=Depends(get_current_user),
    status: str = "",
) -> list:
    return request.app.state.services["market"].list_listings(
        user=user, status=status
    )


@router.post("/market/listings", response_model=m.ListingRead, status_code=201)
def create_listing(
    payload: m.ListingCreate,
    request: Request,
    user=Depends(require_roles(*LISTING_WRITERS)),
) -> dict:
    # The batch must be one this caller may actually act on.
    batches = request.app.state.services["batches"].get_for_user(
        payload.batch_id, user=user
    )
    if batches is None:
        raise HTTPException(status_code=404, detail="Batch not found")
    try:
        return request.app.state.services["market"].create_listing(
            data=payload.model_dump(), user=user
        )
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.post("/market/listings/{listing_id}/withdraw", response_model=m.ListingRead)
def withdraw_listing(
    listing_id: str,
    request: Request,
    user=Depends(require_roles(*LISTING_WRITERS)),
) -> dict:
    try:
        result = request.app.state.services["market"].withdraw_listing(
            listing_id, user=user
        )
    except PermissionError as exc:
        raise _fail(exc) from exc
    if result is None:
        raise HTTPException(status_code=404, detail="Listing not found")
    return result


@router.get("/market/orders", response_model=list[m.OrderRead])
def list_orders(request: Request, user=Depends(get_current_user)) -> list:
    return request.app.state.services["market"].list_orders(user=user)


@router.get("/market/marketplace", response_model=m.MarketplaceRead)
def marketplace(request: Request, user=Depends(get_current_user)) -> dict:
    """One call for the Buyer procurement surface."""
    return request.app.state.services["market"].marketplace(user=user)


@router.post("/market/orders", response_model=m.OrderRead, status_code=201)
def create_order(
    payload: m.OrderCreate,
    request: Request,
    user=Depends(require_roles("buyer", "admin")),
) -> dict:
    try:
        return request.app.state.services["market"].create_order(
            data=payload.model_dump(), user=user
        )
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.post("/market/orders/{order_id}/decide", response_model=m.OrderRead)
def decide_order(
    order_id: str,
    payload: m.OrderDecision,
    request: Request,
    user=Depends(require_roles(*LISTING_WRITERS)),
) -> dict:
    try:
        return request.app.state.services["market"].decide_order(
            order_id,
            accept=payload.accept,
            user=user,
            seller_notes=payload.seller_notes,
        )
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.post("/market/orders/{order_id}/fulfil", response_model=m.OrderRead)
def fulfil_order(
    order_id: str,
    request: Request,
    user=Depends(require_roles(*MARKET_ACTORS)),
) -> dict:
    try:
        return request.app.state.services["market"].fulfil_order(order_id, user=user)
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.post("/market/orders/{order_id}/cancel", response_model=m.OrderRead)
def cancel_order(
    order_id: str,
    request: Request,
    user=Depends(require_roles("buyer", "admin")),
) -> dict:
    try:
        return request.app.state.services["market"].cancel_order(order_id, user=user)
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc
    # ------------------------------------------------------------------ QR ----
@router.get("/qr/packages", response_model=list[m.PackageRead])
def list_packages(
    request: Request,
    user=Depends(require_roles(*PACKAGE_WRITERS)),
    batch_id: str = "",
) -> list:
    return request.app.state.services["qr"].list_packages(user=user, batch_id=batch_id)


@router.post("/qr/packages", response_model=m.PackageRead, status_code=201)
def issue_package(
    payload: m.PackageIssue,
    request: Request,
    user=Depends(require_roles(*PACKAGE_WRITERS)),
) -> dict:
    try:
        return request.app.state.services["qr"].issue_package(
            data=payload.model_dump(), user=user
        )
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.post("/qr/packages/{package_code}/recall", response_model=m.PackageRead)
def recall_package(
    package_code: str,
    request: Request,
    user=Depends(require_roles(*PACKAGE_WRITERS)),
) -> dict:
    try:
        result = request.app.state.services["qr"].recall_package(
            package_code, user=user
        )
    except PermissionError as exc:
        raise _fail(exc) from exc
    if result is None:
        raise HTTPException(status_code=404, detail="Package not found")
    return result


@router.post("/qr/scan", response_model=m.QrScanRead)
def scan_package(
    payload: m.QrScanRequest,
    request: Request,
    user=Depends(get_current_user),
) -> dict:
    """Scan a printed code.

    Authenticated rather than public on purpose: an anonymous scanner could flood
    the scan ledger. The public consumer surface reads the passport API, which is
    the unauthenticated path.
    """
    return request.app.state.services["qr"].scan(payload.package_code, user=user)


@router.get("/qr/scans", response_model=list[m.QrScanRecord])
def suspicious_scans(
    request: Request,
    user=Depends(require_roles(*PACKAGE_WRITERS)),
    limit: int = 50,
) -> list:
    return request.app.state.services["qr"].suspicious_scans(
        user=user, limit=min(int(limit), 200)
    )


@router.get(
    "/qr/packages/{package_code}/scans", response_model=list[m.QrScanRecord]
)
def scan_history(
    package_code: str,
    request: Request,
    user=Depends(require_roles(*PACKAGE_WRITERS)),
) -> list:
    try:
        return request.app.state.services["qr"].scan_history(package_code, user=user)
    except PermissionError as exc:
        raise _fail(exc) from exc


# ----------------------------------------------------------------- van ----
@router.get("/van/dashboard", response_model=m.VanDashboardRead)
def van_dashboard(
    request: Request, user=Depends(require_roles(*VAN_ROLES))
) -> dict:
    return request.app.state.services["van"].dashboard(user=user)


@router.get("/van/visits", response_model=list[m.VanVisitRead])
def list_van_visits(
    request: Request,
    user=Depends(require_roles(*VAN_ROLES)),
    status: str = "",
) -> list:
    return request.app.state.services["van"].list_visits(user=user, status=status)


@router.post("/van/visits", response_model=m.VanVisitRead, status_code=201)
def schedule_visit(
    payload: m.VanVisitCreate,
    request: Request,
    user=Depends(require_roles(*VAN_ROLES)),
) -> dict:
    try:
        return request.app.state.services["van"].schedule_visit(
            data=payload.model_dump(), user=user
        )
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.get("/van/visits/{visit_id}", response_model=m.VanVisitRead)
def get_van_visit(
    visit_id: str,
    request: Request,
    user=Depends(require_roles(*VAN_ROLES)),
) -> dict:
    try:
        result = request.app.state.services["van"].get_visit(visit_id, user=user)
    except PermissionError as exc:
        raise _fail(exc) from exc
    if result is None:
        raise HTTPException(status_code=404, detail="Van visit not found")
    return result


@router.post("/van/visits/{visit_id}/advance", response_model=m.VanVisitRead)
def advance_visit(
    visit_id: str,
    request: Request,
    user=Depends(require_roles(*VAN_ROLES)),
) -> dict:
    """Move a visit to its next state (scheduled -> arrived -> sampled -> done)."""
    try:
        return request.app.state.services["van"].advance_visit(visit_id, user=user)
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.post(
    "/van/visits/{visit_id}/samples", response_model=m.VanSampleRead, status_code=201
)
def collect_sample(
    visit_id: str,
    payload: m.VanSampleCreate,
    request: Request,
    user=Depends(require_roles(*VAN_ROLES)),
) -> dict:
    try:
        return request.app.state.services["van"].collect_sample(
            visit_id, data=payload.model_dump(), user=user
        )
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc


@router.post("/van/samples/{sample_id}/result", response_model=m.VanSampleRead)
def result_sample(
    sample_id: str,
    payload: m.VanSampleResult,
    request: Request,
    user=Depends(require_roles(*VAN_ROLES)),
) -> dict:
    """Record a van field result. This never certifies a batch."""
    try:
        return request.app.state.services["van"].result_sample(
            sample_id, result=payload.result, user=user, notes=payload.notes
        )
    except (ValueError, PermissionError) as exc:
        raise _fail(exc) from exc