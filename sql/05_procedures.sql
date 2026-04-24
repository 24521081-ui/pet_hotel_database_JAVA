-- =========================================================
-- MENU
-- =========================================================

-- II. PROCEDURE
--   1. room_for_multiple_pets                  -- Thủ tục kiểm tra khả năng xếp nhiều thú cưng vào cùng một phòng trống
--   2. sp_validate_and_execute_stock           -- Thủ tục kiểm tra tồn kho và thực hiện trừ kho vật tư tiêu hao
--   3. sp_refund_service_stock                 -- Thủ tục hoàn trả vật tư vào kho khi dịch vụ bị hủy
--   4. sp_assign_pet_to_room                   -- Thủ tục gán thú cưng vào một phòng cụ thể
--   5. update_orders_status                    -- Thủ tục cập nhật trạng thái hóa đơn theo số tiền đã thanh toán
--   6. sp_recalculate_goods_receipt_totals     -- Thủ tục tính lại tổng số lượng và số mặt hàng của phiếu nhập kho
--   7. sp_approve_goods_receipt                -- Thủ tục duyệt phiếu nhập kho và cộng tồn kho
--   8. sp_complete_stock_audit                 -- Thủ tục hoàn tất kiểm kê kho và cập nhật tồn kho thực tế
--   9. sp_record_material_waste                -- Thủ tục ghi nhận hao hụt nguyên liệu và trừ tồn kho
--  10. sp_create_order_from_booking            -- Thủ tục tạo hóa đơn từ booking
--  11. sp_add_payment                          -- Thủ tục ghi nhận thanh toán cho hóa đơn
--  12. sp_update_booking_service_status        -- Thủ tục cập nhật trạng thái dịch vụ đặt thêm
--  13. sp_check_in_booking                     -- Thủ tục check-in booking lưu trú
--  14. sp_check_out_booking                    -- Thủ tục check-out booking lưu trú

-- =========================================================
-- II. PROCEDURE
-- =========================================================

-- 1. Kiểm tra khi một khách hàng muốn gửi nhiều thú cưng vào cùng một phòng trống
CREATE OR REPLACE PROCEDURE room_for_multiple_pets (
    p_booking_room_id IN VARCHAR2,
    p_pet_count       IN NUMBER,
    p_max_pet_weight  IN NUMBER
)
AS
    v_max_pets       type_room.max_pets%TYPE;
    v_max_weight_kg  type_room.max_weight_kg%TYPE;
    v_existing_count NUMBER;
BEGIN
    -- Lấy sức chứa tối đa của loại phòng
    SELECT tr.max_pets, tr.max_weight_kg
    INTO v_max_pets, v_max_weight_kg
    FROM type_room tr
    JOIN room r
        ON r.type_room_id = tr.type_room_id
    JOIN booking_room br
        ON br.room_id = r.room_id
    WHERE br.booking_room_id = p_booking_room_id;

    -- Kiểm tra phòng hiện có thú cưng hay chưa
    SELECT COUNT(*)
    INTO v_existing_count
    FROM booking_room_pet brp
    WHERE brp.booking_room_id = p_booking_room_id;

    IF v_existing_count > 0 THEN
        -- Phòng đã có thú cưng, thủ tục này chỉ áp dụng cho phòng trống
        RAISE_APPLICATION_ERROR(
            -20051,
            'Room is not empty. This procedure only applies to empty rooms.'
        );
    END IF;

    IF p_pet_count > v_max_pets THEN
        -- Số lượng thú cưng vượt quá sức chứa tối đa của phòng
        RAISE_APPLICATION_ERROR(
            -20053,
            'The number of pets exceeds the room capacity. Max pets allowed = ' || v_max_pets
        );
    END IF;

    IF v_max_weight_kg IS NOT NULL
       AND p_max_pet_weight IS NOT NULL
       AND p_max_pet_weight > v_max_weight_kg THEN
        -- Có thú cưng vượt quá giới hạn cân nặng của phòng
        RAISE_APPLICATION_ERROR(
            -20055,
            'One or more pets exceed the room weight limit. Max weight allowed = ' || v_max_weight_kg || ' kg'
        );
    END IF;
END;
/

-- 2. Kiểm tra tồn kho và thực hiện trừ kho vật tư tiêu hao
CREATE OR REPLACE PROCEDURE sp_validate_and_execute_stock (
    p_booking_id IN booking.booking_id%TYPE,
    p_service_id IN services.service_id%TYPE,
    p_pet_id     IN pet.pet_id%TYPE
)
IS
    v_branch_id        booking.branch_id%TYPE;
    v_weight_kg        pet.weight_kg%TYPE;
    v_pet_species      pet.species%TYPE;
    v_service_species  services.species%TYPE;
    v_stock            NUMBER;
    v_usage_conv       NUMBER;
BEGIN
    -- Lấy chi nhánh thực hiện dịch vụ
    SELECT b.branch_id
    INTO v_branch_id
    FROM booking b
    WHERE b.booking_id = p_booking_id;

    -- Lấy cân nặng và loài của thú cưng
    SELECT p.weight_kg, UPPER(p.species)
    INTO v_weight_kg, v_pet_species
    FROM pet p
    WHERE p.pet_id = p_pet_id;

    -- Lấy loài mà dịch vụ áp dụng
    SELECT UPPER(s.species)
    INTO v_service_species
    FROM services s
    WHERE s.service_id = p_service_id;

    -- Kiểm tra dịch vụ có phù hợp với loài thú cưng hay không
    IF v_pet_species <> v_service_species THEN
        -- Dịch vụ không phù hợp với loài thú cưng
        RAISE_APPLICATION_ERROR(
            -20033,
            'This service is not applicable to species: ' || v_pet_species
        );
    END IF;

    -- Duyệt danh sách vật tư tiêu hao theo định mức
    FOR rec IN (
        SELECT sps.product_id,
               sps.usage_amount,
               sps.usage_unit
        FROM service_product_standard sps
        WHERE sps.service_id = p_service_id
          AND v_weight_kg > sps.min_weight_kg
          AND v_weight_kg <= sps.max_weight_kg
    ) LOOP
        -- Quy đổi đơn vị tiêu hao về đơn vị chuẩn
        v_usage_conv := fn_convert_unit(rec.usage_amount, rec.usage_unit);

        -- Khóa dòng tồn kho để tránh race condition
        BEGIN
            SELECT bi.quantity_in_stock
            INTO v_stock
            FROM branch_inventory bi
            WHERE bi.product_id = rec.product_id
              AND bi.branch_id = v_branch_id
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_stock := 0;
        END;

        -- Kiểm tra tồn kho có đủ không
        IF v_stock < v_usage_conv THEN
            -- Tồn kho không đủ để thực hiện dịch vụ
            RAISE_APPLICATION_ERROR(
                -20030,
                'Insufficient stock for product_id = ' || rec.product_id ||
                '. Required = ' || v_usage_conv || ', Available = ' || v_stock
            );
        END IF;

        -- Trừ kho
        UPDATE branch_inventory bi
        SET bi.quantity_in_stock = bi.quantity_in_stock - v_usage_conv,
            bi.last_updated      = SYSTIMESTAMP
        WHERE bi.branch_id = v_branch_id
          AND bi.product_id = rec.product_id;
    END LOOP;
END;
/

-- 3. Hoàn trả vật tư vào kho khi dịch vụ bị hủy
CREATE OR REPLACE PROCEDURE sp_refund_service_stock (
    p_booking_id IN booking.booking_id%TYPE,
    p_service_id IN services.service_id%TYPE,
    p_pet_id     IN pet.pet_id%TYPE
)
IS
    v_branch_id   booking.branch_id%TYPE;
    v_weight_kg   pet.weight_kg%TYPE;
    v_usage_conv  NUMBER;
    v_dummy_stock NUMBER;
BEGIN
    -- Lấy chi nhánh thực hiện dịch vụ
    SELECT b.branch_id
    INTO v_branch_id
    FROM booking b
    WHERE b.booking_id = p_booking_id;

    -- Lấy cân nặng của thú cưng
    SELECT p.weight_kg
    INTO v_weight_kg
    FROM pet p
    WHERE p.pet_id = p_pet_id;

    -- Duyệt danh sách vật tư cần hoàn trả
    FOR rec IN (
        SELECT sps.product_id,
               sps.usage_amount,
               sps.usage_unit
        FROM service_product_standard sps
        WHERE sps.service_id = p_service_id
          AND v_weight_kg > sps.min_weight_kg
          AND v_weight_kg <= sps.max_weight_kg
    ) LOOP
        -- Quy đổi đơn vị về đơn vị chuẩn
        v_usage_conv := fn_convert_unit(rec.usage_amount, rec.usage_unit);

        -- Khóa dòng trước khi cộng trả lại kho
        BEGIN
            SELECT bi.quantity_in_stock
            INTO v_dummy_stock
            FROM branch_inventory bi
            WHERE bi.product_id = rec.product_id
              AND bi.branch_id = v_branch_id
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                CONTINUE;
        END;

        -- Cộng trả lại kho
        UPDATE branch_inventory bi
        SET bi.quantity_in_stock = bi.quantity_in_stock + v_usage_conv,
            bi.last_updated      = SYSTIMESTAMP
        WHERE bi.branch_id = v_branch_id
          AND bi.product_id = rec.product_id;
    END LOOP;
END;
/

-- 4. Gán thú cưng vào một phòng cụ thể
CREATE OR REPLACE PROCEDURE sp_assign_pet_to_room (
    p_booking_room_id IN booking_room.booking_room_id%TYPE,
    p_pet_id          IN pet.pet_id%TYPE
)
IS
    v_current_pets NUMBER;
    v_max_pets     NUMBER;
BEGIN
    -- Đếm số thú cưng hiện tại trong phòng
    SELECT COUNT(*)
    INTO v_current_pets
    FROM booking_room_pet brp
    WHERE brp.booking_room_id = p_booking_room_id;

    -- Lấy sức chứa tối đa của loại phòng
    SELECT tr.max_pets
    INTO v_max_pets
    FROM booking_room br
    JOIN room r
        ON br.room_id = r.room_id
    JOIN type_room tr
        ON r.type_room_id = tr.type_room_id
    WHERE br.booking_room_id = p_booking_room_id;

    -- Kiểm tra sức chứa
    IF v_current_pets >= v_max_pets THEN
        -- Phòng đã đạt giới hạn số lượng thú cưng tối đa
        RAISE_APPLICATION_ERROR(
            -20041,
            'Room capacity has been reached. Max pets allowed = ' || v_max_pets
        );
    END IF;

    -- Thực hiện gán thú cưng vào phòng
    INSERT INTO booking_room_pet (
        booking_room_id,
        pet_id
    )
    VALUES (
        p_booking_room_id,
        p_pet_id
    );
END;
/

-- 5. Cập nhật trạng thái hóa đơn dựa trên tổng tiền đã thanh toán
CREATE OR REPLACE PROCEDURE update_orders_status (
    p_order_id IN orders.order_id%TYPE
)
IS
    v_total_paid   orders.grand_total%TYPE;
    v_grand_total  orders.grand_total%TYPE;
BEGIN
    -- Lấy tổng tiền của hóa đơn
    SELECT ord.grand_total
    INTO v_grand_total
    FROM orders ord
    WHERE ord.order_id = p_order_id;

    -- Tính tổng tiền đã thanh toán thành công
    SELECT NVL(SUM(p.amount), 0)
    INTO v_total_paid
    FROM payments p
    WHERE p.order_id = p_order_id
      AND p.status = 'SUCCESS';

    -- Không cho phép thanh toán vượt quá tổng tiền hóa đơn
    IF v_total_paid > v_grand_total THEN
        -- Tổng tiền thanh toán thành công vượt quá tổng tiền hóa đơn
        RAISE_APPLICATION_ERROR(
            -20071,
            'Total successful payment exceeds the order grand total.'
        );
    END IF;

    -- Chỉ cập nhật trạng thái khi hóa đơn đã đủ điều kiện thanh toán
    IF fn_is_order_ready_to_pay(p_order_id) THEN
        UPDATE orders
        SET status = CASE
                        WHEN v_total_paid = 0 THEN 'PENDING'
                        WHEN v_total_paid < v_grand_total THEN 'PARTIAL'
                        WHEN v_total_paid = v_grand_total THEN 'PAID'
                     END
        WHERE order_id = p_order_id;
    END IF;
END;
/
-- 6. Tính lại tổng số lượng và số mặt hàng của phiếu nhập
CREATE OR REPLACE PROCEDURE sp_recalculate_goods_receipt_totals (
    p_goods_receipt_id IN goods_receipt.goods_receipt_id%TYPE
)
IS
    v_total_quantity   NUMBER;
    v_total_item_count NUMBER;
BEGIN
    SELECT NVL(SUM(grd.quantity), 0),
           COUNT(*)
    INTO v_total_quantity, v_total_item_count
    FROM goods_receipt_detail grd
    WHERE grd.goods_receipt_id = p_goods_receipt_id;

    UPDATE goods_receipt
    SET total_quantity   = v_total_quantity,
        total_item_count = v_total_item_count,
        updated_at       = SYSTIMESTAMP
    WHERE goods_receipt_id = p_goods_receipt_id;
END;
/

-- 7. Duyệt phiếu nhập và cộng tồn kho vào chi nhánh
CREATE OR REPLACE PROCEDURE sp_approve_goods_receipt (
    p_goods_receipt_id IN goods_receipt.goods_receipt_id%TYPE
)
IS
    v_branch_id goods_receipt.branch_id%TYPE;
    v_status    goods_receipt.status%TYPE;
BEGIN
    -- Lấy thông tin phiếu nhập
    SELECT gr.branch_id, gr.status
    INTO v_branch_id, v_status
    FROM goods_receipt gr
    WHERE gr.goods_receipt_id = p_goods_receipt_id
    FOR UPDATE;

    IF v_status = 'APPROVED' THEN
        RAISE_APPLICATION_ERROR(
            -20102,
            'This goods receipt has already been approved.'
            -- Phiếu nhập này đã được duyệt trước đó
        );
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE_APPLICATION_ERROR(
            -20103,
            'Cancelled goods receipt cannot be approved.'
            -- Phiếu nhập đã hủy thì không được duyệt
        );
    END IF;

    -- Cộng tồn kho cho từng sản phẩm trong phiếu nhập
    FOR rec IN (
        SELECT grd.product_id, grd.quantity
        FROM goods_receipt_detail grd
        WHERE grd.goods_receipt_id = p_goods_receipt_id
    ) LOOP
        UPDATE branch_inventory bi
        SET bi.quantity_in_stock = bi.quantity_in_stock + rec.quantity,
            bi.last_updated      = SYSTIMESTAMP
        WHERE bi.branch_id = v_branch_id
          AND bi.product_id = rec.product_id;

        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO branch_inventory (
                branch_id,
                product_id,
                quantity_in_stock,
                reorder_point,
                last_updated
            )
            VALUES (
                v_branch_id,
                rec.product_id,
                rec.quantity,
                0,
                SYSTIMESTAMP
            );
        END IF;
    END LOOP;

    -- Cập nhật trạng thái phiếu nhập
    UPDATE goods_receipt
    SET status     = 'APPROVED',
        updated_at = SYSTIMESTAMP
    WHERE goods_receipt_id = p_goods_receipt_id;
END;
/

-- 8. Hoàn tất kiểm kê và cập nhật tồn kho theo số lượng thực tế
CREATE OR REPLACE PROCEDURE sp_complete_stock_audit (
    p_stock_audit_id IN stock_audit.stock_audit_id%TYPE
)
IS
    v_branch_id stock_audit.branch_id%TYPE;
    v_status    stock_audit.status%TYPE;
BEGIN
    -- Lấy thông tin phiếu kiểm kê
    SELECT sa.branch_id, sa.status
    INTO v_branch_id, v_status
    FROM stock_audit sa
    WHERE sa.stock_audit_id = p_stock_audit_id
    FOR UPDATE;

    IF v_status = 'COMPLETED' THEN
        RAISE_APPLICATION_ERROR(
            -20104,
            'This stock audit has already been completed.'
            -- Phiếu kiểm kê này đã được hoàn tất trước đó
        );
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE_APPLICATION_ERROR(
            -20105,
            'Cancelled stock audit cannot be completed.'
            -- Phiếu kiểm kê đã hủy thì không được hoàn tất
        );
    END IF;

    -- Cập nhật tồn kho theo số lượng thực tế đã kiểm kê
    FOR rec IN (
        SELECT sad.product_id, sad.actual_quantity
        FROM stock_audit_detail sad
        WHERE sad.stock_audit_id = p_stock_audit_id
    ) LOOP
        UPDATE branch_inventory bi
        SET bi.quantity_in_stock = rec.actual_quantity,
            bi.last_updated      = SYSTIMESTAMP
        WHERE bi.branch_id = v_branch_id
          AND bi.product_id = rec.product_id;

        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO branch_inventory (
                branch_id,
                product_id,
                quantity_in_stock,
                reorder_point,
                last_updated
            )
            VALUES (
                v_branch_id,
                rec.product_id,
                rec.actual_quantity,
                0,
                SYSTIMESTAMP
            );
        END IF;
    END LOOP;

    UPDATE stock_audit
    SET status     = 'COMPLETED',
        updated_at = SYSTIMESTAMP
    WHERE stock_audit_id = p_stock_audit_id;
END;
/

-- 9. Ghi nhận hao hụt nguyên liệu và trừ tồn kho
CREATE OR REPLACE PROCEDURE sp_record_material_waste (
    p_material_waste_id IN material_waste.material_waste_id%TYPE,
    p_product_id        IN material_waste.product_id%TYPE,
    p_employee_id       IN material_waste.employee_id%TYPE,
    p_branch_id         IN material_waste.branch_id%TYPE,
    p_waste_quantity    IN material_waste.waste_quantity%TYPE,
    p_reason            IN material_waste.reason%TYPE,
    p_note              IN material_waste.note%TYPE DEFAULT NULL
)
IS
    v_stock NUMBER;
BEGIN
    -- Kiểm tra tồn kho hiện tại
    SELECT NVL(bi.quantity_in_stock, 0)
    INTO v_stock
    FROM branch_inventory bi
    WHERE bi.branch_id = p_branch_id
      AND bi.product_id = p_product_id
    FOR UPDATE;

    IF p_waste_quantity <= 0 THEN
        RAISE_APPLICATION_ERROR(
            -20106,
            'Waste quantity must be greater than zero.'
            -- Số lượng hao hụt phải lớn hơn 0
        );
    END IF;

    IF v_stock < p_waste_quantity THEN
        RAISE_APPLICATION_ERROR(
            -20107,
            'Insufficient stock to record material waste.'
            -- Tồn kho không đủ để ghi nhận hao hụt
        );
    END IF;

    -- Trừ tồn kho
    UPDATE branch_inventory bi
    SET bi.quantity_in_stock = bi.quantity_in_stock - p_waste_quantity,
        bi.last_updated      = SYSTIMESTAMP
    WHERE bi.branch_id = p_branch_id
      AND bi.product_id = p_product_id;

    -- Tạo phiếu hao hụt
    INSERT INTO material_waste (
        material_waste_id,
        product_id,
        employee_id,
        branch_id,
        waste_quantity,
        reason,
        recorded_at,
        status,
        note,
        created_at,
        updated_at
    )
    VALUES (
        p_material_waste_id,
        p_product_id,
        p_employee_id,
        p_branch_id,
        p_waste_quantity,
        p_reason,
        SYSTIMESTAMP,
        'APPROVED',
        p_note,
        SYSTIMESTAMP,
        SYSTIMESTAMP
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20108,
            'Inventory record does not exist for this product in the selected branch.'
            -- Không tìm thấy bản ghi tồn kho của sản phẩm tại chi nhánh này
        );
END;
/
-- 10. Tạo hóa đơn từ booking
CREATE OR REPLACE PROCEDURE sp_create_order_from_booking (
    p_order_id       IN orders.order_id%TYPE,
    p_booking_id     IN booking.booking_id%TYPE,
    p_created_by_emp IN orders.created_by_emp%TYPE
)
IS
    v_customer_id     booking.customer_id%TYPE;
    v_branch_id       booking.branch_id%TYPE;
    v_existing_count  NUMBER;
BEGIN
    -- Kiểm tra booking có tồn tại hay không
    SELECT b.customer_id, b.branch_id
    INTO v_customer_id, v_branch_id
    FROM booking b
    WHERE b.booking_id = p_booking_id;

    -- Kiểm tra booking đã có hóa đơn hay chưa
    SELECT COUNT(*)
    INTO v_existing_count
    FROM orders o
    WHERE o.booking_id = p_booking_id;

    IF v_existing_count > 0 THEN
        -- Booking này đã có hóa đơn
        RAISE_APPLICATION_ERROR(
            -20201,
            'This booking already has an order.'
        );
    END IF;

    -- Tạo hóa đơn ở trạng thái chờ thanh toán
    INSERT INTO orders (
        order_id,
        booking_id,
        customer_id,
        branch_id,
        created_by_emp,
        status,
        subtotal,
        grand_total,
        created_at
    )
    VALUES (
        p_order_id,
        p_booking_id,
        v_customer_id,
        v_branch_id,
        p_created_by_emp,
        'PENDING',
        0,
        0,
        SYSTIMESTAMP
    );

    -- Tạo chi tiết hóa đơn từ các dịch vụ đã đặt
    INSERT INTO order_details (
        order_detail_id,
        order_id,
        booking_id,
        service_id,
        quantity,
        unit_price,
        line_total,
        created_at
    )
    SELECT
        'OD' || LPAD(ROWNUM, 8, '0'),
        p_order_id,
        bs.booking_id,
        bs.service_id,
        1,
        s.base_price,
        s.base_price,
        SYSTIMESTAMP
    FROM booking_services bs
    JOIN services s
        ON bs.service_id = s.service_id
    WHERE bs.booking_id = p_booking_id
      AND bs.status <> 'CANCELLED';

    -- Trigger trg_sync_order_totals sẽ tự cập nhật subtotal và grand_total
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Không tìm thấy booking
        RAISE_APPLICATION_ERROR(
            -20202,
            'Booking does not exist.'
        );
END;
/
-- 12. Ghi nhận thanh toán cho hóa đơn
CREATE OR REPLACE PROCEDURE sp_add_payment (
    p_payment_id     IN payments.payment_id%TYPE,
    p_order_id       IN payments.order_id%TYPE,
    p_payment_method IN payments.payment_method%TYPE,
    p_provider       IN payments.provider%TYPE,
    p_amount         IN payments.amount%TYPE,
    p_note           IN payments.note%TYPE DEFAULT NULL
)
IS
    v_order_status  orders.status%TYPE;
    v_grand_total   orders.grand_total%TYPE;
    v_total_paid    NUMBER;
BEGIN
    -- Lấy thông tin hóa đơn
    SELECT o.status, o.grand_total
    INTO v_order_status, v_grand_total
    FROM orders o
    WHERE o.order_id = p_order_id
    FOR UPDATE;

    IF v_order_status = 'CANCELLED' THEN
        -- Hóa đơn đã hủy thì không được thanh toán
        RAISE_APPLICATION_ERROR(
            -20210,
            'Cancelled order cannot receive payment.'
        );
    END IF;

    IF v_order_status = 'PAID' THEN
        -- Hóa đơn đã thanh toán đủ
        RAISE_APPLICATION_ERROR(
            -20211,
            'This order has already been fully paid.'
        );
    END IF;

    IF p_amount <= 0 THEN
        -- Số tiền thanh toán phải lớn hơn 0
        RAISE_APPLICATION_ERROR(
            -20212,
            'Payment amount must be greater than zero.'
        );
    END IF;

    -- Tính tổng tiền đã thanh toán thành công
    SELECT NVL(SUM(p.amount), 0)
    INTO v_total_paid
    FROM payments p
    WHERE p.order_id = p_order_id
      AND p.status = 'SUCCESS';

    IF v_total_paid + p_amount > v_grand_total THEN
        -- Không cho thanh toán vượt quá tổng tiền hóa đơn
        RAISE_APPLICATION_ERROR(
            -20213,
            'Payment amount exceeds the remaining order balance.'
        );
    END IF;

    -- Ghi nhận thanh toán thành công
    INSERT INTO payments (
        payment_id,
        order_id,
        payment_method,
        provider,
        amount,
        status,
        paid_at,
        note,
        created_at,
        update_at
    )
    VALUES (
        p_payment_id,
        p_order_id,
        p_payment_method,
        p_provider,
        p_amount,
        'SUCCESS',
        SYSTIMESTAMP,
        p_note,
        SYSTIMESTAMP,
        SYSTIMESTAMP
    );

    -- Cập nhật trạng thái hóa đơn
    update_orders_status(p_order_id);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Không tìm thấy hóa đơn
        RAISE_APPLICATION_ERROR(
            -20214,
            'Order does not exist.'
        );
END;
/
-- 13. Cập nhật trạng thái dịch vụ đặt thêm
CREATE OR REPLACE PROCEDURE sp_update_booking_service_status (
    p_booking_service_id IN booking_services.booking_service_id%TYPE,
    p_new_status         IN booking_services.status%TYPE,
    p_note               IN booking_services.note%TYPE DEFAULT NULL
)
IS
    v_old_status booking_services.status%TYPE;
BEGIN
    -- Lấy trạng thái hiện tại của dịch vụ
    SELECT bs.status
    INTO v_old_status
    FROM booking_services bs
    WHERE bs.booking_service_id = p_booking_service_id
    FOR UPDATE;

    -- Kiểm tra trạng thái mới có hợp lệ không
    IF p_new_status NOT IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'DONE', 'CANCELLED') THEN
        -- Trạng thái dịch vụ không hợp lệ
        RAISE_APPLICATION_ERROR(
            -20220,
            'Invalid booking service status.'
        );
    END IF;

    -- Không cho sửa dịch vụ đã hoàn tất hoặc đã hủy
    IF v_old_status IN ('DONE', 'CANCELLED') THEN
        -- Dịch vụ đã hoàn tất hoặc đã hủy thì không nên cập nhật tiếp
        RAISE_APPLICATION_ERROR(
            -20221,
            'Completed or cancelled service cannot be updated.'
        );
    END IF;

    -- Kiểm tra luồng chuyển trạng thái hợp lệ
    IF NOT (
        (v_old_status = 'PENDING' AND p_new_status IN ('SCHEDULED', 'CANCELLED')) OR
        (v_old_status = 'SCHEDULED' AND p_new_status IN ('IN_PROGRESS', 'CANCELLED')) OR
        (v_old_status = 'IN_PROGRESS' AND p_new_status IN ('DONE', 'CANCELLED'))
    ) THEN
        -- Luồng chuyển trạng thái không hợp lệ
        RAISE_APPLICATION_ERROR(
            -20222,
            'Invalid booking service status transition.'
        );
    END IF;

    UPDATE booking_services
    SET status     = p_new_status,
        note       = NVL(p_note, note),
        updated_at = SYSTIMESTAMP
    WHERE booking_service_id = p_booking_service_id;

    -- Trigger trg_bks_inventory_sync sẽ xử lý trừ/hoàn kho nếu cần

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Không tìm thấy dịch vụ đặt thêm
        RAISE_APPLICATION_ERROR(
            -20223,
            'Booking service does not exist.'
        );
END;
/
-- 4. Check-in booking lưu trú
CREATE OR REPLACE PROCEDURE sp_check_in_booking (
    p_booking_id IN booking.booking_id%TYPE
)
IS
    v_status booking.status%TYPE;
BEGIN
    -- Lấy trạng thái hiện tại của booking
    SELECT b.status
    INTO v_status
    FROM booking b
    WHERE b.booking_id = p_booking_id
    FOR UPDATE;

    IF v_status <> 'CONFIRMED' THEN
        -- Chỉ booking đã xác nhận mới được check-in
        RAISE_APPLICATION_ERROR(
            -20230,
            'Only confirmed bookings can be checked in.'
        );
    END IF;

    UPDATE booking
    SET status     = 'CHECKED_IN',
        updated_at = SYSTIMESTAMP
    WHERE booking_id = p_booking_id;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Không tìm thấy booking
        RAISE_APPLICATION_ERROR(
            -20231,
            'Booking does not exist.'
        );
END;
/
-- 14. Check-out booking lưu trú
CREATE OR REPLACE PROCEDURE sp_check_out_booking (
    p_booking_id IN booking.booking_id%TYPE
)
IS
    v_status                booking.status%TYPE;
    v_unfinished_services   NUMBER;
BEGIN
    -- Lấy trạng thái hiện tại của booking
    SELECT b.status
    INTO v_status
    FROM booking b
    WHERE b.booking_id = p_booking_id
    FOR UPDATE;

    IF v_status <> 'CHECKED_IN' THEN
        -- Chỉ booking đang lưu trú mới được check-out
        RAISE_APPLICATION_ERROR(
            -20240,
            'Only checked-in bookings can be checked out.'
        );
    END IF;

    -- Kiểm tra còn dịch vụ nào chưa hoàn tất không
    SELECT COUNT(*)
    INTO v_unfinished_services
    FROM booking_services bs
    WHERE bs.booking_id = p_booking_id
      AND bs.status NOT IN ('DONE', 'CANCELLED');

    IF v_unfinished_services > 0 THEN
        -- Còn dịch vụ chưa hoàn tất nên chưa thể check-out
        RAISE_APPLICATION_ERROR(
            -20241,
            'Booking cannot be checked out because some services are not completed.'
        );
    END IF;

    UPDATE booking
    SET status     = 'CHECKED_OUT',
        updated_at = SYSTIMESTAMP
    WHERE booking_id = p_booking_id;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Không tìm thấy booking
        RAISE_APPLICATION_ERROR(
            -20242,
            'Booking does not exist.'
        );
END;
/
