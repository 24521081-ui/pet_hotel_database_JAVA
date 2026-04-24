-- =========================================================
-- MENU
-- =========================================================
-- III. TRIGGER
--   1. booking_room_no_overlap                  -- Trigger chống trùng lịch đặt phòng
--   2. employee_no_overlap                      -- Trigger ngăn nhân viên bị trùng lịch thực hiện dịch vụ
--   3. booking_service_no_overlap_same_booking  -- Trigger chống trùng thời gian dịch vụ trong cùng một booking
--   4. pet_no_overlap                           -- Trigger ngăn thú cưng bị trùng thời gian lưu trú
--   5. add_pet_same_room                        -- Trigger kiểm tra điều kiện khi thêm thú cưng vào phòng đã có sẵn thú cưng
--   6. trg_payment_time_valid                   -- Trigger kiểm tra thời điểm thanh toán hợp lệ
--   7. trg_bks_inventory_sync                   -- Trigger đồng bộ tồn kho khi thêm hoặc cập nhật dịch vụ
--   8. trg_validate_pet_room_weight             -- Trigger kiểm tra tải trọng thú cưng khi phân vào phòng
--   9. trg_payment_logic_sync                   -- Trigger đồng bộ trạng thái hóa đơn khi có thay đổi thanh toán
--  10. trg_prevent_manual_paid_status           -- Trigger ngăn cập nhật thủ công hóa đơn sang PAID khi chưa đủ điều kiện
--  11. trg_sync_order_totals                    -- Trigger tự động cập nhật subtotal và grand_total khi order_details thay đổi
--  12. trg_grd_fill_line_total                  -- Trigger tự động tính line_total cho chi tiết phiếu nhập kho
--  13. trg_sync_goods_receipt_totals            -- Trigger đồng bộ tổng số lượng và số mặt hàng của phiếu nhập kho
--  14. trg_sad_calc_difference                  -- Trigger tự động tính chênh lệch và tỷ lệ chênh lệch khi kiểm kê kho
--  15. trg_validate_material_waste              -- Trigger kiểm tra dữ liệu hao hụt nguyên liệu khi thao tác trực tiếp

-- =========================================================
-- III. TRIGGER
-- =========================================================

-- 1. Chống trùng lịch đặt phòng
CREATE OR REPLACE TRIGGER booking_room_no_overlap
BEFORE INSERT OR UPDATE ON booking_room
FOR EACH ROW
DECLARE
    v_conflict_booking_id       booking.booking_id%TYPE;
    v_conflict_booking_room_id  booking_room.booking_room_id%TYPE;
BEGIN
    -- Chọn mã booking và booking_room bị trùng để báo lỗi
    SELECT br.booking_id, br.booking_room_id
    INTO v_conflict_booking_id, v_conflict_booking_room_id
    FROM booking_room br
    JOIN booking b_old
        ON br.booking_id = b_old.booking_id
    JOIN booking b_new
        ON b_new.booking_id = :NEW.booking_id
    WHERE br.room_id = :NEW.room_id
      AND br.booking_room_id <> :NEW.booking_room_id
      AND b_old.status <> 'CANCELLED'
      AND b_new.status <> 'CANCELLED'
      AND b_new.checkin_expected_at < b_old.checkout_expected_at
      AND b_new.checkout_expected_at > b_old.checkin_expected_at
      AND ROWNUM = 1;

    -- Phát hiện trùng lịch đặt phòng
    RAISE_APPLICATION_ERROR(
        -20001,
        'Booking room schedule overlap detected. Conflicting booking_id = ' ||
        v_conflict_booking_id || ', booking_room_id = ' || v_conflict_booking_room_id
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/

-- 2. Một nhân viên không thể thực hiện hai dịch vụ cùng một lúc
CREATE OR REPLACE TRIGGER employee_no_overlap
BEFORE INSERT OR UPDATE ON booking_services
FOR EACH ROW
DECLARE
    v_conflict_booking_service_id  booking_services.booking_service_id%TYPE;
    v_conflict_booking_id          booking_services.booking_id%TYPE;
    v_new_end_time                 TIMESTAMP(6) WITH TIME ZONE;
BEGIN
    -- Kiểm tra dữ liệu đầu vào cần thiết
    IF :NEW.employee_id IS NULL
       OR :NEW.service_id IS NULL
       OR :NEW.scheduled_at IS NULL
       OR :NEW.status NOT IN ('SCHEDULED', 'IN_PROGRESS') THEN
        RETURN;
    END IF;

    -- Tính thời gian kết thúc của dịch vụ mới
    SELECT fn_add_minutes(:NEW.scheduled_at, s.duration_minutes)
    INTO v_new_end_time
    FROM services s
    WHERE s.service_id = :NEW.service_id;

    -- Kiểm tra nhân viên có bị trùng lịch với dịch vụ khác không
    SELECT bs.booking_service_id, bs.booking_id
    INTO v_conflict_booking_service_id, v_conflict_booking_id
    FROM booking_services bs
    JOIN services s_old
        ON bs.service_id = s_old.service_id
    WHERE bs.employee_id = :NEW.employee_id
      AND bs.booking_service_id <> :NEW.booking_service_id
      AND bs.status IN ('SCHEDULED', 'IN_PROGRESS')
      AND bs.scheduled_at IS NOT NULL
      AND :NEW.scheduled_at < fn_add_minutes(bs.scheduled_at, s_old.duration_minutes)
      AND v_new_end_time > bs.scheduled_at
      AND ROWNUM = 1;

    -- Phát hiện nhân viên bị trùng lịch thực hiện dịch vụ
    RAISE_APPLICATION_ERROR(
        -20011,
        'Employee schedule overlap detected. Conflicting booking_service_id = ' ||
        v_conflict_booking_service_id || ', booking_id = ' || v_conflict_booking_id
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/

-- 3. Trong cùng một booking, các dịch vụ không được trùng thời gian
CREATE OR REPLACE TRIGGER booking_service_no_overlap_same_booking
BEFORE INSERT OR UPDATE ON booking_services
FOR EACH ROW
DECLARE
    v_conflict_booking_service_id  booking_services.booking_service_id%TYPE;
    v_new_end_time                 TIMESTAMP(6) WITH TIME ZONE;
BEGIN
    -- Kiểm tra dữ liệu đầu vào cần thiết
    IF :NEW.booking_id IS NULL
       OR :NEW.service_id IS NULL
       OR :NEW.scheduled_at IS NULL
       OR :NEW.status NOT IN ('SCHEDULED', 'IN_PROGRESS') THEN
        RETURN;
    END IF;

    -- Tính thời gian kết thúc của dịch vụ mới
    SELECT fn_add_minutes(:NEW.scheduled_at, s.duration_minutes)
    INTO v_new_end_time
    FROM services s
    WHERE s.service_id = :NEW.service_id;

    -- Kiểm tra trùng lịch trong cùng booking
    SELECT bs.booking_service_id
    INTO v_conflict_booking_service_id
    FROM booking_services bs
    JOIN services s_old
        ON bs.service_id = s_old.service_id
    WHERE bs.booking_id = :NEW.booking_id
      AND bs.booking_service_id <> :NEW.booking_service_id
      AND bs.status IN ('SCHEDULED', 'IN_PROGRESS')
      AND bs.scheduled_at IS NOT NULL
      AND :NEW.scheduled_at < fn_add_minutes(bs.scheduled_at, s_old.duration_minutes)
      AND v_new_end_time > bs.scheduled_at
      AND ROWNUM = 1;

    -- Phát hiện dịch vụ bị trùng thời gian trong cùng một booking
    RAISE_APPLICATION_ERROR(
        -20012,
        'Service schedule overlap detected within the same booking. Conflicting booking_service_id = ' ||
        v_conflict_booking_service_id
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/

-- 4. Một thú cưng không được ở hai nơi lưu trú cùng lúc
CREATE OR REPLACE TRIGGER pet_no_overlap
BEFORE INSERT OR UPDATE ON booking_room_pet
FOR EACH ROW
DECLARE
    v_conflict_booking_id       booking.booking_id%TYPE;
    v_conflict_booking_room_id  booking_room.booking_room_id%TYPE;
BEGIN
    -- Kiểm tra thú cưng có bị trùng thời gian lưu trú hay không
    SELECT b_old.booking_id, br_old.booking_room_id
    INTO v_conflict_booking_id, v_conflict_booking_room_id
    FROM booking_room_pet brp_old
    JOIN booking_room br_old
        ON brp_old.booking_room_id = br_old.booking_room_id
    JOIN booking b_old
        ON br_old.booking_id = b_old.booking_id
    JOIN booking_room br_new
        ON br_new.booking_room_id = :NEW.booking_room_id
    JOIN booking b_new
        ON br_new.booking_id = b_new.booking_id
    WHERE brp_old.pet_id = :NEW.pet_id
      AND brp_old.booking_room_id <> :NEW.booking_room_id
      AND b_old.status <> 'CANCELLED'
      AND b_new.status <> 'CANCELLED'
      AND b_new.checkin_expected_at < b_old.checkout_expected_at
      AND b_new.checkout_expected_at > b_old.checkin_expected_at
      AND ROWNUM = 1;

    -- Phát hiện thú cưng bị trùng thời gian lưu trú
    RAISE_APPLICATION_ERROR(
        -20021,
        'Pet stay overlap detected. pet_id = ' || :NEW.pet_id ||
        ' is already assigned to booking_id = ' || v_conflict_booking_id ||
        ', booking_room_id = ' || v_conflict_booking_room_id
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/

-- 5. Thêm thú cưng vào phòng đã có thú cưng trước đó
CREATE OR REPLACE TRIGGER add_pet_same_room
BEFORE INSERT ON booking_room_pet
FOR EACH ROW
DECLARE
    v_max_pets        type_room.max_pets%TYPE;
    v_max_weight_kg   type_room.max_weight_kg%TYPE;
    v_exist_pet_count NUMBER;
    v_new_pet_weight  pet.weight_kg%TYPE;
    v_new_customer_id pet.customer_id%TYPE;
    v_old_customer_id pet.customer_id%TYPE;
BEGIN
    -- Lấy sức chứa tối đa của loại phòng
    SELECT tr.max_pets, tr.max_weight_kg
    INTO v_max_pets, v_max_weight_kg
    FROM type_room tr
    JOIN room r
        ON r.type_room_id = tr.type_room_id
    JOIN booking_room br
        ON br.room_id = r.room_id
    WHERE br.booking_room_id = :NEW.booking_room_id;

    -- Đếm số thú cưng hiện có trong phòng
    SELECT COUNT(*)
    INTO v_exist_pet_count
    FROM booking_room_pet
    WHERE booking_room_id = :NEW.booking_room_id;

    -- Nếu phòng chưa có thú cưng nào thì trigger này không cần kiểm tra tiếp
    IF v_exist_pet_count = 0 THEN
        RETURN;
    END IF;

    IF v_max_pets < 2 THEN
        -- Loại phòng này không cho phép ở ghép
        RAISE_APPLICATION_ERROR(
            -20041,
            'This room type does not allow shared occupancy.'
        );
    END IF;

    IF v_exist_pet_count + 1 > v_max_pets THEN
        -- Vượt quá sức chứa tối đa của phòng
        RAISE_APPLICATION_ERROR(
            -20042,
            'Room capacity exceeded.'
        );
    END IF;

    -- Lấy chủ sở hữu và cân nặng của thú cưng mới
    SELECT customer_id, weight_kg
    INTO v_new_customer_id, v_new_pet_weight
    FROM pet
    WHERE pet_id = :NEW.pet_id;

    -- Lấy chủ sở hữu của thú cưng đã có sẵn trong phòng
    SELECT p.customer_id
    INTO v_old_customer_id
    FROM booking_room_pet brp
    JOIN pet p
        ON brp.pet_id = p.pet_id
    WHERE brp.booking_room_id = :NEW.booking_room_id
      AND ROWNUM = 1;

    IF v_new_customer_id <> v_old_customer_id THEN
        -- Chỉ cho phép thú cưng cùng chủ ở chung phòng
        RAISE_APPLICATION_ERROR(
            -20043,
            'Only pets belonging to the same owner can share a room.'
        );
    END IF;

    IF v_max_weight_kg IS NOT NULL
       AND v_new_pet_weight IS NOT NULL
       AND v_new_pet_weight > v_max_weight_kg THEN
        -- Cân nặng thú cưng vượt quá giới hạn của phòng
        RAISE_APPLICATION_ERROR(
            -20044,
            'Pet weight exceeds the room limit.'
        );
    END IF;
END;
/

-- 6. Kiểm tra thời điểm thanh toán hợp lệ
CREATE OR REPLACE TRIGGER trg_payment_time_valid
BEFORE INSERT OR UPDATE ON payments
FOR EACH ROW
DECLARE
    v_order_created_at  orders.created_at%TYPE;
BEGIN
    -- Nếu thanh toán thành công thì paid_at bắt buộc phải có
    IF :NEW.status = 'SUCCESS' AND :NEW.paid_at IS NULL THEN
        -- Thanh toán thành công thì thời điểm thanh toán không được để trống
        RAISE_APPLICATION_ERROR(
            -20062,
            'Invalid payment data: paid_at must not be NULL when status = SUCCESS.'
        );
    END IF;

    -- Nếu đang chờ xử lý thì paid_at phải để trống
    IF :NEW.status = 'PENDING' AND :NEW.paid_at IS NOT NULL THEN
        -- Trạng thái chờ xử lý thì chưa được có thời điểm thanh toán
        RAISE_APPLICATION_ERROR(
            -20063,
            'Invalid payment data: paid_at must be NULL when status = PENDING.'
        );
    END IF;

    -- Nếu chưa có paid_at thì không cần kiểm tra tiếp
    IF :NEW.paid_at IS NULL THEN
        RETURN;
    END IF;

    -- Lấy thời điểm khởi tạo của hóa đơn tương ứng
    SELECT o.created_at
    INTO v_order_created_at
    FROM orders o
    WHERE o.order_id = :NEW.order_id;

    -- paid_at phải cùng lúc hoặc sau created_at của order
    IF :NEW.paid_at < v_order_created_at THEN
        -- Thời điểm thanh toán phải lớn hơn hoặc bằng thời điểm tạo hóa đơn
        RAISE_APPLICATION_ERROR(
            -20061,
            'Invalid payment time: paid_at must be greater than or equal to order created_at.'
        );
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Mã hóa đơn tham chiếu không tồn tại
        RAISE_APPLICATION_ERROR(
            -20064,
            'Invalid payment data: the referenced order_id does not exist.'
        );
END;
/

-- 7. Tự động đồng bộ kho khi thêm hoặc cập nhật dịch vụ
CREATE OR REPLACE TRIGGER trg_bks_inventory_sync
BEFORE INSERT OR UPDATE ON booking_services
FOR EACH ROW
BEGIN
    -- Khi thêm mới dịch vụ
    IF INSERTING THEN
        IF :NEW.status IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'DONE') THEN
            sp_validate_and_execute_stock(:NEW.booking_id, :NEW.service_id, :NEW.pet_id);
        END IF;
    END IF;

    -- Khi cập nhật trạng thái
    IF UPDATING THEN
        -- Hoàn trả kho nếu hủy dịch vụ
        IF :OLD.status IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'DONE')
           AND :NEW.status = 'CANCELLED' THEN
            sp_refund_service_stock(:NEW.booking_id, :NEW.service_id, :NEW.pet_id);
        END IF;

        -- Trừ lại kho nếu khôi phục dịch vụ từ trạng thái đã hủy
        IF :OLD.status = 'CANCELLED'
           AND :NEW.status IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'DONE') THEN
            sp_validate_and_execute_stock(:NEW.booking_id, :NEW.service_id, :NEW.pet_id);
        END IF;
    END IF;
END;
/

-- 8. Kiểm tra tải trọng thú cưng khi phân vào phòng
CREATE OR REPLACE TRIGGER trg_validate_pet_room_weight
BEFORE INSERT OR UPDATE ON booking_room_pet
FOR EACH ROW
BEGIN
    IF NOT fn_check_pet_weight_limit(:NEW.pet_id, :NEW.booking_room_id) THEN
        -- Cân nặng thú cưng vượt quá giới hạn an toàn của loại phòng
        RAISE_APPLICATION_ERROR(
            -20040,
            'Operational error: pet weight exceeds the safe limit of this room type.'
        );
    END IF;
END;
/

-- 9. Đồng bộ trạng thái hóa đơn khi có thay đổi ở payments
CREATE OR REPLACE TRIGGER trg_payment_logic_sync
FOR INSERT OR UPDATE ON payments
COMPOUND TRIGGER

    AFTER EACH ROW IS
    BEGIN
        IF UPDATING AND (:NEW.order_id <> :OLD.order_id) THEN
            update_orders_status(:OLD.order_id);
        END IF;

        update_orders_status(:NEW.order_id);
    END AFTER EACH ROW;

END;
/

-- 10. Ngăn cập nhật thủ công trạng thái hóa đơn sang PAID khi chưa đủ điều kiện
CREATE OR REPLACE TRIGGER trg_prevent_manual_paid_status
BEFORE UPDATE OF status ON orders
FOR EACH ROW
BEGIN
    -- Chỉ kiểm tra khi có người muốn chuyển trạng thái sang PAID
    IF :NEW.status = 'PAID' THEN
        -- Điều kiện 1: dịch vụ và phòng phải hoàn tất
        IF NOT fn_is_order_ready_to_pay(:NEW.order_id) THEN
            -- Không thể chuyển hóa đơn sang PAID vì dịch vụ hoặc lưu trú chưa hoàn tất
            RAISE_APPLICATION_ERROR(
                -20050,
                'Order cannot be marked as PAID because related services or stays are not yet completed.'
            );
        END IF;
    END IF;
END;
/

-- 11. Tự động cập nhật subtotal và grand_total khi order_details thay đổi
CREATE OR REPLACE TRIGGER trg_sync_order_totals
AFTER INSERT OR UPDATE OR DELETE ON order_details
FOR EACH ROW
DECLARE
    v_booking_id      order_details.booking_id%TYPE;
    v_deposit_amount  booking.deposit_amount%TYPE;
BEGIN
    -- Xác định booking_id liên quan
    v_booking_id := NVL(:NEW.booking_id, :OLD.booking_id);

    -- Lấy tiền cọc của booking, nếu NULL thì xem như 0
    BEGIN
        SELECT NVL(b.deposit_amount, 0)
        INTO v_deposit_amount
        FROM booking b
        WHERE b.booking_id = v_booking_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_deposit_amount := 0;
    END;

    -- Thêm chi tiết hóa đơn mới
    IF INSERTING THEN
        UPDATE orders
        SET subtotal    = subtotal + :NEW.line_total,
            grand_total = subtotal + :NEW.line_total + v_deposit_amount
        WHERE order_id = :NEW.order_id;

    -- Xóa chi tiết hóa đơn
    ELSIF DELETING THEN
        UPDATE orders
        SET subtotal    = subtotal - :OLD.line_total,
            grand_total = subtotal - :OLD.line_total + v_deposit_amount
        WHERE order_id = :OLD.order_id;

    -- Cập nhật chi tiết hóa đơn
    ELSIF UPDATING THEN
        -- Đổi sang hóa đơn khác
        IF :OLD.order_id <> :NEW.order_id THEN
            UPDATE orders
            SET subtotal    = subtotal - :OLD.line_total,
                grand_total = subtotal - :OLD.line_total + v_deposit_amount
            WHERE order_id = :OLD.order_id;

            UPDATE orders
            SET subtotal    = subtotal + :NEW.line_total,
                grand_total = subtotal + :NEW.line_total + v_deposit_amount
            WHERE order_id = :NEW.order_id;

        -- Cập nhật trên cùng một hóa đơn
        ELSE
            UPDATE orders
            SET subtotal    = subtotal + (:NEW.line_total - :OLD.line_total),
                grand_total = subtotal + (:NEW.line_total - :OLD.line_total) + v_deposit_amount
            WHERE order_id = :NEW.order_id;
        END IF;
    END IF;
END;
/
-- 12. Tự động điền line_total cho chi tiết phiếu nhập
CREATE OR REPLACE TRIGGER trg_grd_fill_line_total
BEFORE INSERT OR UPDATE ON goods_receipt_detail
FOR EACH ROW
DECLARE
    v_cost_price product.cost_price%TYPE;
BEGIN
    -- Kiểm tra số lượng nhập
    IF :NEW.quantity IS NULL OR :NEW.quantity <= 0 THEN
        RAISE_APPLICATION_ERROR(
            -20109,
            'Quantity must be greater than zero.'
            -- Số lượng nhập phải lớn hơn 0
        );
    END IF;

    -- Tự động lấy giá vốn hiện tại của sản phẩm để tính thành tiền
    v_cost_price := fn_get_product_cost_price(:NEW.product_id);
    :NEW.line_total := :NEW.quantity * v_cost_price;

    IF :NEW.created_at IS NULL THEN
        :NEW.created_at := SYSTIMESTAMP;
    END IF;

    :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- 13. Đồng bộ tổng số lượng và số mặt hàng của phiếu nhập
CREATE OR REPLACE TRIGGER trg_sync_goods_receipt_totals
AFTER INSERT OR UPDATE OR DELETE ON goods_receipt_detail
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        sp_recalculate_goods_receipt_totals(:NEW.goods_receipt_id);

    ELSIF DELETING THEN
        sp_recalculate_goods_receipt_totals(:OLD.goods_receipt_id);

    ELSIF UPDATING THEN
        IF :OLD.goods_receipt_id <> :NEW.goods_receipt_id THEN
            sp_recalculate_goods_receipt_totals(:OLD.goods_receipt_id);
            sp_recalculate_goods_receipt_totals(:NEW.goods_receipt_id);
        ELSE
            sp_recalculate_goods_receipt_totals(:NEW.goods_receipt_id);
        END IF;
    END IF;
END;
/

-- 14. Tự động tính chênh lệch và tỷ lệ chênh lệch khi kiểm kê
CREATE OR REPLACE TRIGGER trg_sad_calc_difference
BEFORE INSERT OR UPDATE ON stock_audit_detail
FOR EACH ROW
BEGIN
    -- Kiểm tra số lượng hệ thống và số lượng thực tế
    IF :NEW.system_quantity IS NULL OR :NEW.system_quantity < 0 THEN
        RAISE_APPLICATION_ERROR(
            -20110,
            'System quantity must be greater than or equal to zero.'
            -- Số lượng hệ thống phải lớn hơn hoặc bằng 0
        );
    END IF;

    IF :NEW.actual_quantity IS NULL OR :NEW.actual_quantity < 0 THEN
        RAISE_APPLICATION_ERROR(
            -20111,
            'Actual quantity must be greater than or equal to zero.'
            -- Số lượng thực tế phải lớn hơn hoặc bằng 0
        );
    END IF;

    -- Tính độ lệch và tỷ lệ chênh lệch
    :NEW.difference_quantity := :NEW.actual_quantity - :NEW.system_quantity;
    :NEW.difference_rate     := fn_calc_difference_rate(:NEW.system_quantity, :NEW.actual_quantity);

    IF :NEW.created_at IS NULL THEN
        :NEW.created_at := SYSTIMESTAMP;
    END IF;

    :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- 15. Kiểm tra dữ liệu hao hụt nguyên liệu khi thao tác trực tiếp
CREATE OR REPLACE TRIGGER trg_validate_material_waste
BEFORE INSERT OR UPDATE ON material_waste
FOR EACH ROW
DECLARE
    v_stock NUMBER;
BEGIN
    IF :NEW.waste_quantity IS NULL OR :NEW.waste_quantity <= 0 THEN
        RAISE_APPLICATION_ERROR(
            -20112,
            'Waste quantity must be greater than zero.'
            -- Số lượng hao hụt phải lớn hơn 0
        );
    END IF;

    -- Khi insert trực tiếp bằng SQL thì vẫn kiểm tra tồn kho
    SELECT NVL(bi.quantity_in_stock, 0)
    INTO v_stock
    FROM branch_inventory bi
    WHERE bi.branch_id = :NEW.branch_id
      AND bi.product_id = :NEW.product_id;

    IF INSERTING AND v_stock < :NEW.waste_quantity THEN
        RAISE_APPLICATION_ERROR(
            -20113,
            'Insufficient stock for material waste recording.'
            -- Tồn kho không đủ để ghi nhận hao hụt
        );
    END IF;

    IF :NEW.recorded_at IS NULL THEN
        :NEW.recorded_at := SYSTIMESTAMP;
    END IF;

    IF :NEW.created_at IS NULL THEN
        :NEW.created_at := SYSTIMESTAMP;
    END IF;

    :NEW.updated_at := SYSTIMESTAMP;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20114,
            'Inventory record does not exist for this product in the selected branch.'
            -- Không tìm thấy tồn kho của sản phẩm tại chi nhánh được chọn
        );
END;
/
