-- =========================================================
-- II. FUNCTION
-- =========================================================
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
/*
MÔ TẢ:
Tra cứu số lượng tồn kho thực tế của một vật tư tại một chi nhánh cụ thể.
Sử dụng NVL để trả về 0 nếu dữ liệu rỗng và xử lý ngoại lệ khi chưa từng nhập kho.
*/
CREATE OR REPLACE FUNCTION fn_get_available_stock( 
    p_product_id IN product.product_id%TYPE,
    p_branch_id  IN branch.branch_id%TYPE
) RETURN NUMBER IS
    v_stock NUMBER;
BEGIN
    SELECT 
        NVL(BI.quantity_in_stock, 0) 
    INTO 
        v_stock
    FROM 
        branch_inventory BI
    WHERE 
        BI.product_id = p_product_id 
        AND BI.branch_id = p_branch_id;
        
    RETURN v_stock;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0; 
END;
/
-- dùng để tính thời gian thực hiện một dịch vụ của nhân viên từ lúc lập lịch
/*
MÔ TẢ:
Quy đổi đơn vị định mức (L, KG) về đơn vị lưu kho nhỏ nhất (ML, G) để tính toán chính xác.
*/
CREATE OR REPLACE FUNCTION fn_convert_unit( 
    p_amount NUMBER,
    p_unit   VARCHAR2
) RETURN NUMBER IS
BEGIN
    IF p_unit IN ('L', 'KG') THEN
        RETURN p_amount * 1000;
    ELSE 
        RETURN p_amount;
    END IF;
END;
/
/*
MÔ TẢ:
Hàm kiểm tra khối lượng của thú cưng có phù hợp với giới hạn tải trọng của loại phòng tương ứng hay không.
Trả về TRUE nếu hợp lệ (hoặc phòng không có giới hạn), trả về FALSE nếu vượt tải.
*/
CREATE OR REPLACE FUNCTION fn_check_pet_weight_limit (
    p_pet_id IN pet.pet_id%TYPE,
    p_booking_room_id IN booking_room.booking_room_id%TYPE
) RETURN BOOLEAN IS
    v_pet_weight        pet.weight_kg%TYPE;
    v_room_max_weight   type_room.max_weight_kg%TYPE;
BEGIN
    -- 1. Lấy trọng lượng thực tế của thú cưng
    SELECT
        P.weight_kg
    INTO
        v_pet_weight
    FROM
        pet P
    WHERE
        P.pet_id = p_pet_id;

    -- 2. Lấy giới hạn trọng lượng của loại phòng
    SELECT
        TR.max_weight_kg
    INTO
        v_room_max_weight
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

    -- 3. Đánh giá logic
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
CREATE OR REPLACE FUNCTION fn_is_order_ready_to_pay
(
    v_order_id IN orders.order_id%TYPE
) -- Tham số truyền vào
RETURN BOOLEAN
IS
-- Biến 
    v_count_not_done_service NUMBER;
    v_count_not_checked_out_room NUMBER;
BEGIN
    -- 1. Đếm các dịch vụ chưa hoàn thành (Khác DONE hoặc CANCELLED)
    SELECT COUNT(*) INTO v_count_not_done_service
    FROM order_details od
    JOIN booking_services bs ON od.booking_id = bs.booking_id AND od.service_id = bs.service_id
    WHERE od.order_id = v_order_id
      AND bs.status NOT IN ('DONE', 'CANCELLED');

    -- 2. Đếm các phiếu đặt phòng chưa hoàn thành (Khác CHECKED_OUT hoặc CANCELLED)
    SELECT COUNT(*) INTO v_count_not_checked_out_room
    FROM order_details od
    JOIN booking b ON od.booking_id = b.booking_id
    WHERE od.order_id = v_order_id
      AND b.status NOT IN ('CHECKED_OUT', 'CANCELLED');

    -- Nếu cả hai đều bằng 0 thì mới sẵn sàng thanh toán
    IF v_count_not_done_service = 0 AND v_count_not_checked_out_room = 0 THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
/
