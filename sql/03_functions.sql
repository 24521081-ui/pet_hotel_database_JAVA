-- =========================================================
-- MENU
-- =========================================================

-- I. FUNCTION
--   1. fn_add_minutes                    -- Hàm cộng thêm số phút vào một mốc thời gian
--   2. fn_get_available_stock            -- Hàm lấy số lượng tồn kho hiện có của sản phẩm tại chi nhánh
--   3. fn_convert_unit                   -- Hàm quy đổi đơn vị về đơn vị chuẩn nhỏ nhất g,kg,ml,l
--   4. fn_check_pet_weight_limit         -- Hàm kiểm tra cân nặng thú cưng có phù hợp với giới hạn phòng hay không
--   5. fn_is_order_ready_to_pay          -- Hàm kiểm tra hóa đơn đã đủ điều kiện để thanh toán hay chưa
--   6. fn_calc_difference_rate           -- Hàm tính tỷ lệ chênh lệch giữa số lượng hệ thống và số lượng thực tế khi kiểm kê
--   7. fn_get_product_cost_price         -- Hàm lấy giá vốn hiện tại của sản phẩm

-- =========================================================
-- I. FUNCTION
-- =========================================================

-- 1. Cộng thêm số phút vào thời điểm bắt đầu
CREATE OR REPLACE FUNCTION fn_add_minutes (
    p_start_time TIMESTAMP WITH TIME ZONE,
    p_minutes    NUMBER
)
RETURN TIMESTAMP WITH TIME ZONE
AS
BEGIN
    RETURN p_start_time + NUMTODSINTERVAL(p_minutes, 'MINUTE');
END;
/

-- 2. Lấy số lượng tồn kho hiện có của một sản phẩm tại một chi nhánh
CREATE OR REPLACE FUNCTION fn_get_available_stock (
    p_product_id IN product.product_id%TYPE,
    p_branch_id  IN branch.branch_id%TYPE
)
RETURN NUMBER
IS
    v_stock NUMBER;
BEGIN
    SELECT NVL(bi.quantity_in_stock, 0)
    INTO v_stock
    FROM branch_inventory bi
    WHERE bi.product_id = p_product_id
      AND bi.branch_id = p_branch_id;

    RETURN v_stock;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
END;
/

-- 3. Quy đổi đơn vị về đơn vị chuẩn nhỏ nhất
CREATE OR REPLACE FUNCTION fn_convert_unit (
    p_amount IN NUMBER,
    p_unit   IN VARCHAR2
)
RETURN NUMBER
IS
BEGIN
    IF UPPER(TRIM(p_unit)) IN ('L', 'KG') THEN
        RETURN p_amount * 1000;
    ELSIF UPPER(TRIM(p_unit)) IN ('ML', 'G') THEN
        RETURN p_amount;
    ELSE
        -- Đơn vị không hợp lệ
        RAISE_APPLICATION_ERROR(
            -20070,
            'Invalid unit: ' || p_unit
        );
    END IF;
END;
/

-- 4. Kiểm tra cân nặng thú cưng có phù hợp với giới hạn của phòng hay không
CREATE OR REPLACE FUNCTION fn_check_pet_weight_limit (
    p_pet_id          IN pet.pet_id%TYPE,
    p_booking_room_id IN booking_room.booking_room_id%TYPE
)
RETURN BOOLEAN
IS
    v_pet_weight      pet.weight_kg%TYPE;
    v_room_max_weight type_room.max_weight_kg%TYPE;
BEGIN
    -- Lấy cân nặng thực tế của thú cưng
    SELECT p.weight_kg
    INTO v_pet_weight
    FROM pet p
    WHERE p.pet_id = p_pet_id;

    -- Lấy giới hạn cân nặng của loại phòng
    SELECT tr.max_weight_kg
    INTO v_room_max_weight
    FROM booking_room br
    JOIN room r
        ON br.room_id = r.room_id
    JOIN type_room tr
        ON r.type_room_id = tr.type_room_id
    WHERE br.booking_room_id = p_booking_room_id;

    -- Nếu phòng không giới hạn cân nặng hoặc thú cưng không vượt ngưỡng thì hợp lệ
    IF v_room_max_weight IS NULL OR v_pet_weight <= v_room_max_weight THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN FALSE;
END;
/

-- 5. Kiểm tra hóa đơn đã đủ điều kiện để thanh toán hay chưa
CREATE OR REPLACE FUNCTION fn_is_order_ready_to_pay (
    p_order_id IN orders.order_id%TYPE
)
RETURN BOOLEAN
IS
    v_count_not_done_service      NUMBER;
    v_count_not_checked_out_room  NUMBER;
BEGIN
    -- Đếm các dịch vụ chưa hoàn tất
    SELECT COUNT(*)
    INTO v_count_not_done_service
    FROM order_details od
    JOIN booking_services bs
        ON od.booking_id = bs.booking_id
       AND od.service_id = bs.service_id
    WHERE od.order_id = p_order_id
      AND bs.status NOT IN ('DONE', 'CANCELLED');

    -- Đếm các booking lưu trú chưa hoàn tất
    SELECT COUNT(*)
    INTO v_count_not_checked_out_room
    FROM order_details od
    JOIN booking b
        ON od.booking_id = b.booking_id
    WHERE od.order_id = p_order_id
      AND b.status NOT IN ('CHECKED_OUT', 'CANCELLED');

    IF v_count_not_done_service = 0
       AND v_count_not_checked_out_room = 0 THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
/
-- 6. Tính tỷ lệ chênh lệch kiểm kê
CREATE OR REPLACE FUNCTION fn_calc_difference_rate (
    p_system_quantity IN NUMBER,
    p_actual_quantity IN NUMBER
)
RETURN NUMBER
IS
BEGIN
    IF p_system_quantity IS NULL OR p_system_quantity = 0 THEN
        RETURN NULL;
    END IF;

    RETURN ROUND(ABS(p_actual_quantity - p_system_quantity) / p_system_quantity * 100, 2);
END;
/

-- 7. Lấy giá vốn hiện tại của sản phẩm
CREATE OR REPLACE FUNCTION fn_get_product_cost_price (
    p_product_id IN product.product_id%TYPE
)
RETURN NUMBER
IS
    v_cost_price product.cost_price%TYPE;
BEGIN
    SELECT p.cost_price
    INTO v_cost_price
    FROM product p
    WHERE p.product_id = p_product_id;

    RETURN NVL(v_cost_price, 0);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20101,
            'Product does not exist.'
            -- Không tìm thấy sản phẩm
        );
END;
/
