/*MENU
1. Customer
2. Branch 
3. Employee
4. App_user
5. Pet
6. Category_Product
7. Prodcut
8. Branch_Inventory
9. Category_Services
10. Services
11. Type_room
12. Room
13. Booking
14. Booking_Servieces
15. Orders
16. Orders_details
17. Payments
18. Booking_room
19. Pet_health_record
20. Booking_room_pet
21. Service_product_standard
*/
-- =========================================================
-- 1. CUSTOMER
-- =========================================================
CREATE TABLE customer (
    customer_id      VARCHAR2(10) NOT NULL,
    full_name        NVARCHAR2(120) NOT NULL,
    email            NVARCHAR2(254),
    phone            NVARCHAR2(20) NOT NULL,
    address          NVARCHAR2(120),
    note             CLOB,
    created_at       TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_customer PRIMARY KEY (customer_id),
    CONSTRAINT uq_customer_phone UNIQUE (phone),
    CONSTRAINT uq_customer_email UNIQUE (email)
);
-- =========================================================
-- 2. BRANCH
-- =========================================================
CREATE TABLE branch (
    branch_id        VARCHAR2(10) NOT NULL,
    branch_name      NVARCHAR2(120) NOT NULL,
    phone            VARCHAR2(20),
    email            VARCHAR2(254),
    address          NVARCHAR2(120) NOT NULL,
    is_active        NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_branch PRIMARY KEY (branch_id),
    CONSTRAINT uq_branch_email UNIQUE (email),
    CONSTRAINT ck_branch_is_active CHECK (is_active IN (0,1))
    -- 0: là ngừng hoạt động, 1 là đang hoạt động
);
-- =========================================================
-- 3. EMPLOYEE
-- =========================================================
CREATE TABLE employee (
    employee_id      VARCHAR2(10) NOT NULL,
    branch_id        VARCHAR2(10) NOT NULL,
    full_name        NVARCHAR2(120) NOT NULL,
    email            VARCHAR2(254),
    phone            VARCHAR2(20) NOT NULL,
    hire_date        TIMESTAMP(6) WITH TIME ZONE,
    status_code      NVARCHAR2(20) NOT NULL,
    note             CLOB,
    CONSTRAINT pk_employee PRIMARY KEY (employee_id),
    CONSTRAINT uq_employee_email UNIQUE (email),
    CONSTRAINT uq_employee_phone UNIQUE (phone),
    CONSTRAINT fk_employee_branch FOREIGN KEY (branch_id) REFERENCES branch(branch_id),
    CONSTRAINT ck_employee_status CHECK (status_code IN ('WORKING','ON_LEAVE','RESIGNED'))
    --Working: đang làm việc, On_Leave: đang trong kì nghỉ phép, Resigned: đã nghỉ việc
);
-- =========================================================
-- 4. APP_USER
-- =========================================================
CREATE TABLE app_user (
    employee_id      VARCHAR2(10) NOT NULL,
    password_hash    NVARCHAR2(255),
    role_emp         NVARCHAR2(20) NOT NULL,
    user_name        NVARCHAR2(254) NOT NULL,
    is_active        NUMBER(1) DEFAULT 1 NOT NULL,
    last_login       TIMESTAMP(6) WITH TIME ZONE,
    created_at       TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_app_user PRIMARY KEY (employee_id),
    CONSTRAINT fk_app_user_employee FOREIGN KEY (employee_id) REFERENCES employee(employee_id),
    CONSTRAINT uq_app_user_username UNIQUE (user_name),
    CONSTRAINT ck_app_user_is_active CHECK (is_active IN (0,1)),
    --0: INACTIVE; 1: ACTIVE
    CONSTRAINT ck_app_user_role CHECK (role_emp IN (0,1,2,3,4,5))
    -- 0 = Customer: khách hàng
    -- 1 = Receptionist: nhân viên lễ tân
    -- 2 = Pet Care Staff: nhân viên chăm sóc thú cưng
    -- 3 = Warehouse Staff: nhân viên quản lý kho
    -- 4 = Branch Manager: nhân viên quản lý chi nhánh
    -- 5 = CEO: giám đốc
);
-- =========================================================
-- 5. PET
-- =========================================================
CREATE TABLE pet (
    pet_id           VARCHAR2(10) NOT NULL,
    customer_id      VARCHAR2(10) NOT NULL,
    pet_name         NVARCHAR2(20) NOT NULL,
    species          NVARCHAR2(30) NOT NULL,
    breed            NVARCHAR2(60),
    sex              NVARCHAR2(10),
    weight_kg        NUMBER(5,2),
    special_note     CLOB,
    created_at       TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_pet PRIMARY KEY (pet_id),
    CONSTRAINT fk_pet_customer FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    CONSTRAINT ck_pet_weight CHECK (weight_kg IS NULL OR weight_kg > 0),
    CONSTRAINT ck_pet_sex CHECK (sex IS NULL OR sex IN ('Male','Female'))
);
-- =========================================================
-- 6. CATEGORY_PRODUCT: loại sản phẩm
-- =========================================================
CREATE TABLE category_product (
    product_category_id VARCHAR2(10) NOT NULL,
    category_name       NVARCHAR2(100) NOT NULL,
    created_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_category_product PRIMARY KEY (product_category_id),
    CONSTRAINT uq_category_product_name UNIQUE (category_name)
);
-- =========================================================
-- 7. PRODUCT
-- =========================================================
CREATE TABLE product (
    product_id          VARCHAR2(10) NOT NULL,
    product_category_id VARCHAR2(10) NOT NULL,
    product_name        NVARCHAR2(160) NOT NULL,
    unit                VARCHAR2(30),
    cost_price          NUMBER(12,2) NOT NULL,
    created_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_product PRIMARY KEY (product_id),
    CONSTRAINT fk_product_category FOREIGN KEY (product_category_id) REFERENCES category_product(product_category_id),
    CONSTRAINT ck_product_cost_price CHECK (cost_price >= 0)
);
-- =========================================================
-- 8. BRANCH_INVENTORY
-- =========================================================
CREATE TABLE branch_inventory (
    branch_id           VARCHAR2(10) NOT NULL,
    product_id          VARCHAR2(10) NOT NULL,
    quantity_in_stock   NUMBER(10) DEFAULT 0 NOT NULL, -- số lượng tồn kho
    reorder_point       NUMBER(10),-- số lượng cảnh báo để nhập hàng lại 
    last_updated        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_branch_inventory PRIMARY KEY (branch_id, product_id),
    CONSTRAINT fk_inventory_branch FOREIGN KEY (branch_id) REFERENCES branch(branch_id),
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES product(product_id),
    CONSTRAINT ck_inventory_qty CHECK (quantity_in_stock >= 0),
    CONSTRAINT ck_inventory_reorder CHECK (reorder_point IS NULL OR reorder_point >= 0)
);
-- =========================================================
-- 9. CATEGORY_SERVICES: tên loại dịch vụ   
-- =========================================================
CREATE TABLE category_services (
    service_category_id VARCHAR2(10) NOT NULL,
    category_name       NVARCHAR2(80) NOT NULL,
    note                CLOB,
    created_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_category_services PRIMARY KEY (service_category_id),
    CONSTRAINT uq_category_services_name UNIQUE (category_name)
);
-- =========================================================
-- 10. SERVICES
-- =========================================================
CREATE TABLE services (
    service_id           VARCHAR2(10) NOT NULL,
    service_category_id  VARCHAR2(10) NOT NULL,
    service_name         NVARCHAR2(120) NOT NULL,
    species             NVARCHAR2(20) NOT NULL,
    description_sv       CLOB,
    base_price           NUMBER(12,2) DEFAULT 0 NOT NULL,
    duration_minutes     NUMBER(4),-- thời lượng thực hiện dịch vụ 
    is_active            NUMBER(1) DEFAULT 1 NOT NULL,
    created_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_services PRIMARY KEY (service_id),
    CONSTRAINT fk_services_category FOREIGN KEY (service_category_id) REFERENCES category_services(service_category_id),
    CONSTRAINT ck_services_price CHECK (base_price >= 0),
    CONSTRAINT ck_services_duration CHECK (duration_minutes IS NULL OR duration_minutes > 0),
    CONSTRAINT ck_services_active CHECK (is_active IN (0,1))
    --0: INACTIVE; 1: ACTIVE
);
-- =========================================================
-- 11. TYPE_ROOM
-- =========================================================
CREATE TABLE type_room (
    type_room_id         VARCHAR2(10) NOT NULL,
    type_name            NVARCHAR2(80) NOT NULL,
    note                 CLOB,
    max_pets             NUMBER(2) NOT NULL,
    max_weight_kg        NUMBER(5,2),
    base_price_per_day NUMBER(12,2) NOT NULL,
    is_active            NUMBER(1) DEFAULT 1 NOT NULL,
    created_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_type_room PRIMARY KEY (type_room_id),
    CONSTRAINT ck_type_room_max_pets CHECK (max_pets > 0),
    CONSTRAINT ck_type_room_max_weight CHECK (max_weight_kg IS NULL OR max_weight_kg > 0),
    CONSTRAINT ck_type_room_active CHECK (is_active IN (0,1)),
    --0: INACTIVE; 1:ACTIVE
    CONSTRAINT ck_type_room_price CHECK (base_price_per_day >= 0),
    CONSTRAINT ck_type_room_name CHECK (type_name IN ('STANDARD','PREMIUM','SUITE'))
    --STANDARD: Phòng tiêu chuẩn
    --PREMIUM: Thuộc loại phòng vip, đầy đủ tiện nghi
    --SUITE: Phòng rộng hơn 2 phòng còn lại, đầy đủ tiện nghi hơn
);
-- =========================================================
-- 12. ROOM
-- =========================================================
CREATE TABLE room (
    room_id                VARCHAR2(10) NOT NULL,
    branch_id              VARCHAR2(10) NOT NULL,
    type_room_id           VARCHAR2(10) NOT NULL,
    room_number            NVARCHAR2(10) NOT NULL,
    status                 NVARCHAR2(20) NOT NULL,
    created_at             TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_room PRIMARY KEY (room_id),
    CONSTRAINT fk_room_branch FOREIGN KEY (branch_id) REFERENCES branch(branch_id),
    CONSTRAINT fk_room_type FOREIGN KEY (type_room_id) REFERENCES type_room(type_room_id),
    CONSTRAINT ck_room_status CHECK (status IN ('AVAILABLE','IN_USE','MAINTENANCE'))
    --AVAILABLE: Trống
    --IN_USE: Đang hoạt động
    --MAINTENANCE: Bảo trì
);

-- =========================================================
-- 13. BOOKING
-- =========================================================
CREATE TABLE booking (
    booking_id              VARCHAR2(10) NOT NULL,
    customer_id             VARCHAR2(10) NOT NULL,
    branch_id               VARCHAR2(10) NOT NULL,
    checkin_expected_at     TIMESTAMP(6) WITH TIME ZONE,
    checkout_expected_at    TIMESTAMP(6) WITH TIME ZONE,
    status                  NVARCHAR2(20) NOT NULL,
    deposit_amount          NUMBER(12,2),
    special_note            CLOB,
    created_at              TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at              TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_booking PRIMARY KEY (booking_id),
    CONSTRAINT fk_booking_customer FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    CONSTRAINT fk_booking_branch FOREIGN KEY (branch_id) REFERENCES branch(branch_id),
    CONSTRAINT ck_booking_status CHECK (status IN ('PENDING','CONFIRMED','CHECKED_IN','CHECKED_OUT','CANCELLED')),
    CONSTRAINT ck_booking_time CHECK (
        checkin_expected_at IS NULL
        OR checkout_expected_at IS NULL
        OR checkout_expected_at > checkin_expected_at
    )
);

-- =========================================================
-- 14. BOOKING_SERVICES
-- =========================================================
CREATE TABLE booking_services (
    booking_service_id    VARCHAR2(10) NOT NULL,
    booking_id            VARCHAR2(10) NOT NULL,
    service_id            VARCHAR2(10),
    employee_id           VARCHAR2(10),
    scheduled_at          TIMESTAMP(6) WITH TIME ZONE,
    status                NVARCHAR2(20) NOT NULL,
    note                  CLOB,
    created_at            TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at            TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_booking_services PRIMARY KEY (booking_service_id),
    CONSTRAINT fk_bks_booking FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
    CONSTRAINT fk_bks_service FOREIGN KEY (service_id) REFERENCES services(service_id),
    CONSTRAINT fk_bks_employee FOREIGN KEY (employee_id) REFERENCES employee(employee_id),
    CONSTRAINT ck_bks_status CHECK (status IN ('PENDING','SCHEDULED','IN_PROGRESS','DONE','CANCELLED'))
);

-- =========================================================
-- 15. ORDERS
-- =========================================================
CREATE TABLE orders (
    order_id             VARCHAR2(10) NOT NULL,
    customer_id          VARCHAR2(10) NOT NULL,
    branch_id            VARCHAR2(10) NOT NULL,
    created_by_emp       VARCHAR2(10) NOT NULL,
    status               VARCHAR2(20) NOT NULL,
    grand_total          NUMBER(12,2) NOT NULL,
    created_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    CONSTRAINT fk_orders_branch FOREIGN KEY (branch_id) REFERENCES branch(branch_id),
    CONSTRAINT fk_orders_employee FOREIGN KEY (created_by_emp) REFERENCES employee(employee_id),
    CONSTRAINT ck_orders_total CHECK (grand_total >= 0),
    CONSTRAINT ck_orders_status CHECK (status IN ('PENDING','PAID','PARTIAL','CANCELLED','REFUNDED'))
    --PENDING: Hóa đơn đã tạo nhưng chưa thanh toán
    --PAID: Đã thanh toán đầy đủ
    --PARTIAL: Đã thanh toán 1 phần -> tiền cọc
    --CANCELLED: Hủy hóa đơn
    --REFUND: Hoàn tiền
);
-- =========================================================
-- 16. ORDER_DETAILS
-- =========================================================
CREATE TABLE order_details (
    order_detail_id      VARCHAR2(10) NOT NULL,
    booking_id           VARCHAR2(10),
    service_id           VARCHAR2(10),
    order_id             VARCHAR2(10) NOT NULL,
    note                 CLOB,
    quantity             NUMBER(10,2) DEFAULT 1 NOT NULL,
    unit_price           NUMBER(12,2) NOT NULL,
    line_total           NUMBER(12,2) NOT NULL,
    created_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_order_details PRIMARY KEY (order_detail_id),
    CONSTRAINT fk_od_booking FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
    CONSTRAINT fk_od_service FOREIGN KEY (service_id) REFERENCES services(service_id),
    CONSTRAINT fk_od_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT ck_od_qty CHECK (quantity > 0),
    CONSTRAINT ck_od_unit_price CHECK (unit_price >= 0),
    CONSTRAINT ck_od_line_total CHECK (line_total >= 0)
);--để ý công thức của linetotal

-- =========================================================
-- 17. PAYMENTS
-- =========================================================
CREATE TABLE payments (
    payment_id           VARCHAR2(10) NOT NULL,
    order_id             VARCHAR2(10) NOT NULL,
    payment_method       VARCHAR2(30) NOT NULL,
    provider             VARCHAR2(50),
    amount               NUMBER(12,2) NOT NULL,
    status               VARCHAR2(20) NOT NULL,
    paid_at              TIMESTAMP(6) WITH TIME ZONE,
    note                 CLOB,
    created_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at           TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_payments PRIMARY KEY (payment_id),
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT ck_payments_amount CHECK (amount > 0),
    CONSTRAINT ck_payments_method CHECK (payment_method IN ('CASH','BANK_TRANSFER','CARD','EWALLET')),
    CONSTRAINT ck_payments_status CHECK (status IN ('PENDING','SUCCESS','FAILED','REFUNDED')),
    --Pending: đang chờ xử lý, chưa xác nhận thành công
    CONSTRAINT ck_payment_status_paid_at
    CHECK (
    (status IN ('SUCCESS', 'REFUNDED') AND paid_at IS NOT NULL)
    OR
    (status IN ('PENDING', 'FAILED') AND paid_at IS NULL)
    )

);
-- =========================================================
-- 18. Booking_room
-- =========================================================
CREATE TABLE Booking_room(
    booking_room_id VARCHAR2(10) NOT NULL,
    booking_id      VARCHAR2(10) NOT NULL,
    room_id         VARCHAR2(10) NOT NULL,
    assigned_at     TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    note            CLOB,
    CONSTRAINT pk_booking_room PRIMARY KEY(booking_room_id),
    CONSTRAINT fk_bkr_booking_id FOREIGN KEY(booking_id) REFERENCES Booking(booking_id),
    CONSTRAINT fk_bkr_room_id FOREIGN KEY(room_id) REFERENCES Room(room_id),
    CONSTRAINT uq_booking_room UNIQUE (booking_id, room_id)
    );
-- =========================================================
-- 19. PET_HEALTH_RECORD
-- =========================================================
CREATE TABLE pet_health_record (
    health_record_id     VARCHAR2(10) NOT NULL,
    pet_id               VARCHAR2(10) NOT NULL,
    booking_id           VARCHAR2(10) NOT NULL,
    recorded_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    note                 CLOB,
    status               NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT hpr_pk_01 PRIMARY KEY (health_record_id),
    CONSTRAINT hpr_fk_pet_01 FOREIGN KEY (pet_id) REFERENCES pet(pet_id),
    CONSTRAINT hpr_fk_booking_01 FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
    CONSTRAINT hpr_ck_status_01 CHECK (status IN (0,1))
);
-- =========================================================
-- 20. Booking_room_pet
-- =========================================================
CREATE TABLE Booking_room_pet (
    booking_room_id VARCHAR2(10) NOT NULL,
    pet_id          VARCHAR2(10) NOT NULL,
    assigned_at     TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    note            CLOB,
    CONSTRAINT pk_brp PRIMARY KEY(booking_room_id,pet_id),
    CONSTRAINT fk_brp_pet FOREIGN KEY (pet_id) REFERENCES pet(pet_id),
    CONSTRAINT fk_brp_booking_room FOREIGN KEY (booking_room_id) REFERENCES booking_room(booking_room_id)
);
-- =========================================================
-- 21. Service_product_standard
-- =========================================================
CREATE TABLE service_product_standard (
    standard_id         VARCHAR2(10) NOT NULL,
    service_id          VARCHAR2(10) NOT NULL,
    product_id          VARCHAR2(10) NOT NULL,
    min_weight_kg       NUMBER(5,2) NOT NULL,
    max_weight_kg       NUMBER(5,2) NOT NULL,
    usage_amount        NUMBER(10,2) NOT NULL,
    usage_unit          VARCHAR2(10) NOT NULL,
    note                CLOB,
    created_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    updated_at          TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    CONSTRAINT pk_service_product_standard PRIMARY KEY (standard_id),
    CONSTRAINT fk_sps_service FOREIGN KEY (service_id) REFERENCES services(service_id),
    CONSTRAINT fk_sps_product FOREIGN KEY (product_id) REFERENCES product(product_id),
    CONSTRAINT ck_sps_weight_min CHECK (min_weight_kg >= 0),
    CONSTRAINT ck_sps_weight_max CHECK (max_weight_kg > 0),
    CONSTRAINT ck_sps_weight_range CHECK (max_weight_kg > min_weight_kg),
    CONSTRAINT ck_sps_usage_amount CHECK (usage_amount > 0),
    CONSTRAINT ck_sps_usage_unit CHECK (usage_unit IN ('ML','L','G','KG')),
    CONSTRAINT ck_sps_species CHECK (species IN ('DOG','CAT'))
);
