-- =========================================================
-- II. PROCEDURE
-- =========================================================
-- kiểm tra xem khi một khách hàng muốn gửi 1 lần nhiều thú cưng vào 1 phòng
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
    SELECT tr.max_pets, tr.max_weight_kg
    INTO v_max_pets, v_max_weight_kg
    FROM type_room tr
    JOIN room r ON r.type_room_id = tr.type_room_id
    JOIN booking_room br ON br.room_id = r.room_id
    WHERE br.booking_room_id = :NEW.booking_room_id;

    SELECT COUNT(*)
    INTO v_existing_count
    FROM booking_room_pet brp
    WHERE brp.booking_room_id = p_booking_room_id;

    IF v_existing_count > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20051,
            'Room is not empty. This procedure only applies to empty rooms.');
    END IF;

    IF p_pet_count > v_max_pets THEN
        RAISE_APPLICATION_ERROR(
            -20053,
            'The number of pets exceeds the room capacity. Max pets allowed = ' ||v_max_pets
        );
    END IF;

    IF v_max_weight_kg IS NOT NULL
       AND p_max_pet_weight IS NOT NULL
       AND p_max_pet_weight > v_max_weight_kg THEN
        RAISE_APPLICATION_ERROR(
            -20055,
            'One or more pets exceed the room weight limit. Max weight allowed = ' ||v_max_weight_kg||' kg'
        );
    END IF;
END;
/
/*
MÔ TẢ:
Thủ tục kiểm tra khả năng cung ứng và thực hiện trừ kho vật tư tiêu hao.
Cơ chế:
- So khớp Loài (Species) giữa thú cưng và dịch vụ.
- Sử dụng FOR UPDATE để khóa dòng tồn kho, ngăn chặn tranh chấp dữ liệu (Race Condition).
*/
CREATE OR REPLACE PROCEDURE sp_validate_and_execute_stock (
    p_booking_id IN booking.booking_id%TYPE,
    p_service_id IN services.service_id%TYPE,
    p_pet_id     IN pet.pet_id%TYPE 
) IS
    v_branch_id        booking.branch_id%TYPE;
    v_weight_kg        pet.weight_kg%TYPE;
    v_pet_species      pet.species%TYPE;
    v_service_species  services.species%TYPE;
    v_stock            NUMBER;
    v_usage_conv       NUMBER;
BEGIN
    -- 1. Lấy chi nhánh thực hiện
    SELECT 
        B.branch_id 
    INTO 
        v_branch_id 
    FROM 
        booking B 
    WHERE 
        B.booking_id = p_booking_id;

    -- 2. Lấy cân nặng và loài của thú cưng
    SELECT 
        P.weight_kg,
        UPPER(P.species)
    INTO 
        v_weight_kg,
        v_pet_species
    FROM 
        pet P 
    WHERE 
        P.pet_id = p_pet_id;

    -- 3. Lấy loài được quy định cho dịch vụ này
    SELECT 
        UPPER(S.species)
    INTO 
        v_service_species
    FROM 
        services S 
    WHERE 
        S.service_id = p_service_id;

    -- 4. Kiểm tra chéo loài để đảm bảo dịch vụ phù hợp
    IF v_pet_species != v_service_species THEN
        RAISE_APPLICATION_ERROR(-20033, 'LỖI LOGIC: Dịch vụ này không dành cho loài ' || v_pet_species);
    END IF;

    -- 5. Duyệt định mức vật tư tiêu hao
    FOR rec IN (
        SELECT 
            SPS.product_id, 
            SPS.usage_amount, 
            SPS.usage_unit
        FROM 
            service_product_standard SPS
        WHERE 
            SPS.service_id = p_service_id
            AND v_weight_kg > SPS.min_weight_kg 
            AND v_weight_kg <= SPS.max_weight_kg
    ) LOOP
        
        -- 5.1 Quy đổi đơn vị tiêu hao
        v_usage_conv := fn_convert_unit(rec.usage_amount, rec.usage_unit);
        
        -- 5.2 Khóa dòng tồn kho để đảm bảo tính tuần tự của giao dịch
        BEGIN
            SELECT 
                BI.quantity_in_stock 
            INTO 
                v_stock
            FROM 
                branch_inventory BI
            WHERE 
                BI.product_id = rec.product_id
                AND BI.branch_id = v_branch_id
            FOR UPDATE; -- KHÓA DÒNG
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_stock := 0;
        END;

        -- 5.3 Kiểm tra tồn kho
        IF v_stock < v_usage_conv THEN
            RAISE_APPLICATION_ERROR(-20030, 'LỖI TỒN KHO: Sản phẩm ' || rec.product_id || ' không đủ. Cần: ' || v_usage_conv || ', Có: ' || v_stock);
        END IF;

        -- 5.4 Cập nhật trừ kho
        UPDATE 
            branch_inventory BI
        SET 
            BI.quantity_in_stock = BI.quantity_in_stock - v_usage_conv,
            BI.last_updated = SYSTIMESTAMP
        WHERE 
            BI.branch_id = v_branch_id 
            AND BI.product_id = rec.product_id;

    END LOOP;
END;
/
/*
MÔ TẢ:
Thủ tục hoàn trả vật tư vào kho khi dịch vụ bị hủy bỏ.
Sử dụng FOR UPDATE để tránh việc cộng dồn sai lệch khi có nhiều tiến trình chạy song song.
*/
CREATE OR REPLACE PROCEDURE sp_refund_service_stock (
    p_booking_id IN booking.booking_id%TYPE,
    p_service_id IN services.service_id%TYPE,
    p_pet_id     IN pet.pet_id%TYPE 
) IS
    v_branch_id   booking.branch_id%TYPE;
    v_weight_kg   pet.weight_kg%TYPE;
    v_usage_conv  NUMBER;
    v_dummy_stock NUMBER;
BEGIN
    SELECT 
        B.branch_id 
    INTO 
        v_branch_id 
    FROM 
        booking B 
    WHERE 
        B.booking_id = p_booking_id;

    SELECT 
        P.weight_kg
    INTO 
        v_weight_kg
    FROM 
        pet P 
    WHERE 
        P.pet_id = p_pet_id;

    FOR rec IN (
        SELECT 
            SPS.product_id, 
            SPS.usage_amount, 
            SPS.usage_unit
        FROM 
            service_product_standard SPS
        WHERE 
            SPS.service_id = p_service_id
            AND v_weight_kg > SPS.min_weight_kg 
            AND v_weight_kg <= SPS.max_weight_kg
    ) LOOP
        
        v_usage_conv := fn_convert_unit(rec.usage_amount, rec.usage_unit);

        -- Khóa dòng trước khi thực hiện cộng trả lại
        BEGIN
            SELECT 
                BI.quantity_in_stock 
            INTO 
                v_dummy_stock
            FROM 
                branch_inventory BI
            WHERE 
                BI.product_id = rec.product_id
                AND BI.branch_id = v_branch_id
            FOR UPDATE; -- KHÓA DÒNG
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                CONTINUE;
        END;

        UPDATE 
            branch_inventory BI
        SET 
            BI.quantity_in_stock = BI.quantity_in_stock + v_usage_conv,
            BI.last_updated = SYSTIMESTAMP
        WHERE 
            BI.branch_id = v_branch_id 
            AND BI.product_id = rec.product_id;

    END LOOP;
END;
/
/*
MÔ TẢ:
Thủ tục thực hiện gán thú cưng vào một phòng cụ thể.
Kiểm tra sức chứa tối đa (max_pets) hiện tại của phòng trước khi thực hiện lệnh INSERT.
(Lệnh INSERT thành công sẽ tự động kích hoạt Trigger kiểm tra cân nặng phía trên).
*/
CREATE OR REPLACE PROCEDURE sp_assign_pet_to_room (
    p_booking_room_id IN booking_room.booking_room_id%TYPE,
    p_pet_id IN pet.pet_id%TYPE
) IS
    v_current_pets NUMBER;
    v_max_pets     NUMBER;
BEGIN
    -- 1. Đếm số lượng thú cưng hiện tại đang có trong phòng này
    SELECT
        COUNT(*)
    INTO
        v_current_pets
    FROM
        booking_room_pet BRP
    WHERE
        BRP.booking_room_id = p_booking_room_id;

    -- 2. Lấy sức chứa tối đa (max_pets) của loại phòng đó
    SELECT
        TR.max_pets
    INTO
        v_max_pets
    FROM
        booking_room BR
    JOIN
        room R
    ON
        BR.room_id = R.room_id
    JOIN
        type_room TR
    ON
        R.type_room_id = TR.type_room_id
    WHERE
        BR.booking_room_id = p_booking_room_id;

    -- 3. Kiểm tra sức chứa
    IF v_current_pets >= v_max_pets THEN
        RAISE_APPLICATION_ERROR(-20041, 'LỖI SỨC CHỨA: Phòng này đã đạt số lượng thú cưng tối đa (' || v_max_pets || ' bé).');
    END IF;

    -- 4. Nếu thỏa mãn số lượng, thực hiện chèn dữ liệu
    INSERT INTO
        booking_room_pet (
            booking_room_id,
            pet_id
        )
    VALUES (
        p_booking_room_id,
        p_pet_id
    );

END;
/
CREATE OR REPLACE PROCEDURE update_orders_status --update_orders_status  
(
    v_order_id IN orders.order_id%TYPE
) -- Tham số
IS
--Khai báo biến
    CURSOR cursor_orders --Trả về tổng tiền đã chuyển khoản của hóa đơn đó
        IS SELECT
            SUM(P.amount)
        FROM
            payments P
        WHERE 
            P.order_id = v_order_id AND
            P.status = 'SUCCESS';
    v_total_paid orders.grand_total%TYPE;
    v_grand_total orders.grand_total%TYPE;
BEGIN
    -- Lấy tổng tiền cần thanh toán trước
    SELECT
        ORD.grand_total
    INTO 
        v_grand_total
    FROM 
        orders ORD
    WHERE 
        ORD.order_id = v_order_id;
    OPEN cursor_orders;
    FETCH cursor_orders INTO v_total_paid;
    IF v_total_paid > v_grand_total THEN
            RAISE_APPLICATION_ERROR(-20001, 'LỖI: Tổng tiền thanh toán ('||v_total_paid||') vượt quá hóa đơn ('||v_grand_total||').'); -- Tại sao lại ghi lỗi -20001
    END IF;
    UPDATE orders
    SET
        status = CASE
            WHEN v_grand_total = v_total_paid THEN 'PAID'
            WHEN v_total_paid < v_grand_total THEN 'PARTIAL'
        END
    WHERE 
        v_order_id = order_id AND
        fn_is_order_ready_to_pay(v_order_id) = true; -- Nếu mà dịch vụ của hệ thống chưa hoàn thành thì chưa được chuyển trạng thái order sang PAID
    CLOSE cursor_orders;
END;
