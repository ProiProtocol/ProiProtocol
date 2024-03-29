// Copyright (c) ProiProtocol, Inc.
module ProiProtocol::shop {
    
    use std::string::{Self, String};
    use std::vector;

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as dof;
    use sui::dynamic_field as df;
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::event;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self,VecMap};
    use sui::vec_set::{Self,VecSet};

    use ProiProtocol::proi::{Self, PROI};

    const ENotPublisher: u64 = 0;
    const EAlreadyExistGameID: u64 = 1;
    const ENotExistGameID: u64 = 2;
    const ENotExistLicenseID: u64 = 3;
    const EInsufficientFee: u64 = 4;
    const EInsufficientFunds: u64 = 5;
    const ENotOwner: u64 = 6;
    const EInvalidDiscountRate: u64 = 7;
    const ENotEnoughAuthCount: u64 = 8;
    const ENotAllowedResell: u64 = 9;
    const ENotExistItemID: u64 = 10;
    const EOutOfIndex: u64 = 11;
    const EWrongLanguageCodePair: u64 = 12;
    const ELockedSale: u64 = 13;
    const ENoPROIs: u64 = 14;


    const MaxDiscount: u64 = 10000;
    const MaxPurchaseFeeRate: u64 = 10000;
    const MaxRoyaltyRate: u64 = 10000;

    // Objests
    struct ProiShop has key {
        id: UID,
        submission_fee: u64,    // PROI. Update with Oracle (ex Switchboard)
        purchase_fee_rate: u64, 
        game_list: VecMap<String, Game>,
        purchase_fee_storage: PurchaseFeeStorage,
        submission_fee_storage: SubmissionFeeStorage
    }

    struct ProiCap has key, store{
        id: UID,
        for: ID
    }

    struct Game has key, store {
        id: UID,
        game_id: String,
        name: String,
        thumbnail: vector<u8>,
        image_url: VecSet<vector<u8>>,
        video_url: VecSet<vector<u8>>,
        short_intro: VecMap<vector<u8>, vector<u8>>,
        intro: vector<u8>,
        release_date: vector<u8>,
        genre: vector<u8>,
        developer: vector<u8>,
        publisher: vector<u8>,
        language: VecSet<vector<u8>>,
        platform: VecSet<vector<u8>>,
        system_requirements: vector<u8>,
        sale_lock: bool,
        license_list: VecMap<ID, License> 
    }

    struct GamePubCap has key, store{
        id: UID,
        for: ID
    }

    struct PurchaseFeeStorage has key, store{
        id: UID,
        fees: Balance<PROI>
    }

    struct SubmissionFeeStorage has key, store {
        id: UID,
        fees: Balance<PROI>
    }

    struct ResellerShop has key {
        id: UID,
        item_list: VecMap<ID, ResellerItem> 
    }
    
    struct ResellerItem has key, store {
        id: UID,
        reseller: String,
        description: String,
        price: u64,
        item: LicenseKey
    }

    struct License has key, store {
        id: UID,
        name: String,
        thumbnail: String,
        short_intro: VecMap<vector<u8>, vector<u8>>,
        publisher_price: u64,
        discount_rate: u64,
        royalty_rate: u64,
        permit_resale: bool,
        limit_auth_count: u64,
    }

    struct LicenseKey has key, store{
        id: UID,
        game_id: String,
        license_id: ID,
        auth_count: u64,
        license_name: String,
        license_thumbnail: String,
        owner: address,
        user: address
    }

    /// Events
    struct RegisterGameEvent has copy, drop{
        game_id: String
    }
    struct CreateLicenseEvent has copy, drop{
        game_id: String,
        license_id: ID
    }
    struct PurchaseEvent has copy, drop{
        game_id: String,
        license_id: ID,
        license_key_id: ID
    }
    struct ResellEvent has copy, drop{
        item_id: ID
    }

    fun init(ctx: &mut TxContext) {        
        let p_storage = PurchaseFeeStorage{
            id: object::new(ctx),
            fees: balance::zero<PROI>()
        };
        let s_storage = SubmissionFeeStorage{
            id: object::new(ctx),
            fees: balance::zero<PROI>()
        };

        let proi_shop = ProiShop {
            id: object::new(ctx),
            submission_fee: 100,    // 100 USD
            purchase_fee_rate: 100, // 1%, 100 of 10000
            game_list: vec_map::empty<String, Game>(),
            purchase_fee_storage: p_storage,
            submission_fee_storage: s_storage
        };

        transfer::transfer(ProiCap{
            id: object::new(ctx),
            for: object::id(&proi_shop)
        }, tx_context::sender(ctx));

        transfer::share_object(proi_shop);

        transfer::share_object(ResellerShop {
            id: object::new(ctx),
            item_list: vec_map::empty<ID, ResellerItem>()
        });
    }

    // Regist game
    public entry fun regist_game(
        proi_shop: &mut ProiShop,
        game_id_bytes: vector<u8>,
        name_bytes: vector<u8>,
        thumbnail: vector<u8>,
        image_url: vector<vector<u8>>,
        video_url: vector<vector<u8>>,
        short_intro: vector<vector<vector<u8>>>,
        intro: vector<u8>,
        release_date: vector<u8>,
        genre: vector<u8>,
        developer: vector<u8>,
        publisher: vector<u8>,
        language: vector<vector<u8>>,
        platform: vector<vector<u8>>,
        system_requirements: vector<u8>,
        sale_lock: bool,
        submission_fee: Coin<PROI>,
        ctx: &mut TxContext
    ) {
        // Check game_id
        let game_id = string::utf8(game_id_bytes);
        assert!(vec_map::contains(&proi_shop.game_list, &game_id) == false, EAlreadyExistGameID);
        
        // Check submit fee
        let proi_fee_amount = change_price_usd_to_proi(proi_shop.submission_fee);
        assert!(proi_fee_amount == coin::value(&submission_fee), EInsufficientFee);
        df::add<String, u64>(&mut proi_shop.id, game_id, coin::value(&submission_fee));
        
        // Pay a fee
        let fee_storage = &mut proi_shop.submission_fee_storage;
        let balance_fee = coin::into_balance(submission_fee);
        balance::join(&mut fee_storage.fees, balance_fee);

        // Create Game object
        let game = create_game_object(
            game_id,
            name_bytes,
            thumbnail,
            image_url,
            video_url,
            short_intro,
            intro,
            release_date,
            genre,
            developer,
            publisher,
            language,
            platform,
            system_requirements,
            sale_lock,
            ctx
        );


        let cap = GamePubCap{
            id: object::new(ctx),
            for: object::id(&game)
        };
        let game_list = &mut proi_shop.game_list;
        vec_map::insert(game_list, game_id, game);

        // Transfer cpapbility
        transfer::transfer(cap, tx_context::sender(ctx));

        // Emit Event
        event::emit(RegisterGameEvent{game_id})
    }

    public entry fun update_game(){
        // TODO : Update Game Object
    }

    fun create_game_object(
        game_id: String,
        name_bytes: vector<u8>,
        thumbnail: vector<u8>,
        v_image_url: vector<vector<u8>>,
        v_video_url: vector<vector<u8>>,
        v_short_intro: vector<vector<vector<u8>>>,
        intro: vector<u8>,
        release_date: vector<u8>,
        genre: vector<u8>,
        developer: vector<u8>,
        publisher: vector<u8>,
        v_language: vector<vector<u8>>,
        v_platform: vector<vector<u8>>,
        system_requirements: vector<u8>,
        sale_lock: bool,
        ctx: &mut TxContext
    ): Game{
        // Image list
        let image_url = vec_set::empty<vector<u8>>();
        let i = 0;
        let n = vector::length(&v_image_url);
        while (i < n){
            vec_set::insert(&mut image_url, *vector::borrow(&v_image_url, i));
            i = i + 1;
        };

        // Video list
        let video_url = vec_set::empty<vector<u8>>();
        i = 0;
        n = vector::length(&v_video_url);
        while (i < n){
            vec_set::insert(&mut video_url, *vector::borrow(&v_video_url, i));
            i = i + 1;
        };

        // Short intro
        let short_intro = vec_map::empty<vector<u8>, vector<u8>>();
        i = 0;
        n = vector::length(&v_short_intro);
        while (i < n){
            let pair = *vector::borrow(&v_short_intro, i);
            // key - value pair check 
            assert!(vector::length(&pair) == 2, 0);
            
            // key: ISO 639 Alpha-2 Language code
            let key = *vector::borrow(&pair, 0);
            let key_str = string::utf8(key);
            assert!(string::length(&key_str) == 2, 0);
            let value =  *vector::borrow(&pair, 1);

            vec_map::insert(&mut short_intro, key, value);
            i = i + 1;
        };
        
        // Support language list
        let language = vec_set::empty<vector<u8>>();
        i = 0;
        n = vector::length(&v_language);
        while (i < n){
            vec_set::insert(&mut language, *vector::borrow(&v_language, i));
            i = i + 1;
        };

        // Support plaform list
        let platform = vec_set::empty<vector<u8>>();
        i = 0;
        n = vector::length(&v_platform);
        while (i < n){
            vec_set::insert(&mut platform, *vector::borrow(&v_platform, i));
            i = i + 1;
        };

        let game = Game{
            id: object::new(ctx),
            game_id,
            name: string::utf8(name_bytes),
            thumbnail,
            image_url,
            video_url,
            short_intro,
            intro,
            release_date,
            genre,
            developer,
            publisher,
            language,
            platform,
            system_requirements,
            sale_lock,
            license_list: vec_map::empty<ID, License>(),
        };
        game
    }

    /// Create License
    public entry fun create_license(
        proi_shop: &mut ProiShop,
        cap: &GamePubCap,
        game_id_bytes: vector<u8>,
        name_bytes: vector<u8>,
        thumbnail: vector<u8>,
        v_short_intro: vector<vector<vector<u8>>>,
        publisher_price: u64,
        discount_rate: u64,
        royalty_rate: u64,
        permit_resale: bool,
        limit_auth_count: u64,
        ctx: &mut TxContext
    ){
        // Data Validate
        assert!(discount_rate >= 0, EInvalidDiscountRate);
        assert!(discount_rate <= MaxDiscount, EInvalidDiscountRate);

        // Game Publisher Capability
        let game_id = string::utf8(game_id_bytes);
        let game = get_game_mut(&mut proi_shop.game_list, &game_id);
        assert!(object::id(game) == cap.for, ENotPublisher);

        // Create License object
        let short_intro = vec_map::empty<vector<u8>, vector<u8>>();
        let i = 0;
        let n = vector::length(&v_short_intro);
        while (i < n){
            let pair = *vector::borrow(&v_short_intro, i);
            // key - value pair check 
            assert!(vector::length(&pair) == 2, 0);
            
            // key: ISO 639 Alpha-2 Language code
            let key = *vector::borrow(&pair, 0);
            let key_str = string::utf8(key);
            assert!(string::length(&key_str) == 2, 0);
            let value =  *vector::borrow(&pair, 1);

            vec_map::insert(&mut short_intro, key, value);
            i = i + 1;
        };

        let new_license = License{
            id: object::new(ctx),
            name: string::utf8(name_bytes),
            thumbnail: string::utf8(thumbnail),
            short_intro,
            publisher_price,
            discount_rate,
            royalty_rate,
            permit_resale,
            limit_auth_count,
        };
        let license_id = object::id(&new_license);
        vec_map::insert(&mut game.license_list, license_id, new_license);

        // Emit Event
        event::emit(CreateLicenseEvent{game_id, license_id})
    }

    public entry fun update_license(){
        // TODO : Update License Object
    } 

    /// Purchase License
    public entry fun purchase(
        proi_shop: &mut ProiShop,
        game_id_bytes: vector<u8>,
        license_id: ID,
        paid: Coin<PROI>,
        buyer: address,
        ctx: &mut TxContext
    ){
        // Load License
        let game_id = string::utf8(game_id_bytes);
        let game = get_game(&proi_shop.game_list, &game_id);
        let license = get_license(&proi_shop.game_list, &game_id, &license_id);
        
        // Sale On/Off
        assert!(game.sale_lock == false, ELockedSale);

        // Discount
        let publisher_price = license.publisher_price;
        if (license.discount_rate > 0){
            publisher_price = publisher_price - (publisher_price * license.discount_rate / MaxDiscount);
        };
        let proi_price = change_price_usd_to_proi(publisher_price);
        assert!(proi_price == coin::value(&paid), EInsufficientFunds);
        
        // Pay a fee
        if (proi_price > 0){
            // truncate decimal places
            let fee = (proi_price * proi_shop.purchase_fee_rate / MaxPurchaseFeeRate);
            if (fee > 0){
                let purchase_fee = coin::take(coin::balance_mut(&mut paid), fee, ctx);
                let fee_storage = &mut proi_shop.purchase_fee_storage;
                balance::join(&mut fee_storage.fees, coin::into_balance(purchase_fee));
            }
        };
        
        // Save paid
        if (dof::exists_<String>(&proi_shop.id, game_id)) {
            coin::join(
                dof::borrow_mut<String, Coin<PROI>>(&mut proi_shop.id, game_id),
                paid
            )
        } else {
            dof::add(&mut proi_shop.id, game_id, paid)
        };

        // Create LicenseKey
        let default_address:address = @0x00;
        let license_key = LicenseKey{
            id: object::new(ctx),
            game_id,
            license_id,
            auth_count: 0,
            license_name: license.name,
            license_thumbnail: license.thumbnail,
            owner: buyer,
            user: default_address
        };
        
        // Emit Event
        event::emit(PurchaseEvent{
            game_id,
            license_id,
            license_key_id: object::id(&license_key)
        });
        transfer::public_transfer(license_key, buyer)
    }

    /// Authenticate in game sdk
    public entry fun authenticate(
        proi_shop: &mut ProiShop,
        license_key: &mut LicenseKey,
        ctx: &mut TxContext
    ){
        // Check Owner
        let sender = tx_context::sender(ctx);
        assert!(license_key.owner == sender, ENotOwner);

        // Authenticate
        if (license_key.user != sender){
            let license = get_license(
                &proi_shop.game_list,
                &license_key.game_id,
                &license_key.license_id
            );

            assert!(license.limit_auth_count > license_key.auth_count, ENotEnoughAuthCount);

            license_key.auth_count = license_key.auth_count + 1;
            license_key.user = sender;
        };
    }
    
    public fun get_game(
        game_list: & VecMap<String, Game>,
        game_id: & String
    ): & Game{
        assert!(vec_map::contains(game_list, game_id) == true, ENotExistGameID);
        vec_map::get(game_list, game_id)
    }

    public fun get_game_mut(
        game_list: &mut VecMap<String, Game>,
        game_id: & String
    ): &mut Game{
        assert!(vec_map::contains(game_list, game_id) == true, ENotExistGameID);
        vec_map::get_mut(game_list, game_id)
    }

    public fun get_license(
        game_list: & VecMap<String, Game>,
        game_id: & String,
        license_id: & ID
    ): & License{
        let game = get_game(game_list, game_id);
        assert!(vec_map::contains(&game.license_list, license_id) == true, ENotExistLicenseID);
        vec_map::get(& game.license_list, license_id)
    }

    public fun get_license_by_idx(
        game: & Game,
        idx: u64
    ): & License{
        assert!(vec_map::size(&game.license_list) > idx, EOutOfIndex);
        let (_, license) = vec_map::get_entry_by_idx(& game.license_list, idx);
        license
    }

    /// List LicenseKey for reselling
    public entry fun list_license_key(
        proi_shop: &mut ProiShop,
        reseller_shop: &mut ResellerShop,
        license_key: LicenseKey,
        reseller_bytes: vector<u8>,
        description_bytes: vector<u8>,
        price: u64,
        ctx: &mut TxContext
    ){
        // Check Owner
        let sender = tx_context::sender(ctx);
        assert!(license_key.owner == sender, ENotOwner);

        // Check permit resell
        let license = get_license(
            &proi_shop.game_list,
            &license_key.game_id,
            &license_key.license_id
        );
        assert!(license.permit_resale == true, ENotAllowedResell);

        // Check auth count
        assert!(license.limit_auth_count > license_key.auth_count, ENotEnoughAuthCount);
        
        // Create reselling item
        let reseller = string::utf8(reseller_bytes);
        let description = string::utf8(description_bytes);
        let item = ResellerItem{
            id: object::new(ctx),
            reseller,
            description,
            price,
            item: license_key
        };

        // Save reselling list
        let item_list = &mut reseller_shop.item_list;
        vec_map::insert(item_list, object::id(&item), item);
    }

    /// Resell Item
    public entry fun resell(
        proi_shop: &mut ProiShop,
        reseller_shop: &mut ResellerShop,
        game_id_bytes: vector<u8>,
        item_id: ID,
        paid: Coin<PROI>,
        buyer: address,
        ctx: &mut TxContext
    ){
        let game_id = string::utf8(game_id_bytes);

        // Load Item
        let item_list = &mut reseller_shop.item_list;
        assert!(vec_map::contains(item_list, &item_id) == true, ENotExistItemID);
        let item_info = vec_map::get<ID, ResellerItem>(item_list, &item_id);

        // Check paid
        let proi_price = change_price_usd_to_proi(item_info.price);
        assert!(proi_price == coin::value(&paid), EInsufficientFunds);

        // Royalty
        let license_key = &item_info.item;
        let license = get_license(
            &proi_shop.game_list,
            &license_key.game_id,
            &license_key.license_id
        );

        if (license.royalty_rate > 0){
            // truncate decimal places
            let royalty_price = (proi_price * license.royalty_rate / MaxRoyaltyRate);
            if (royalty_price > 0){
                let royalty = coin::take(coin::balance_mut(&mut paid), royalty_price, ctx);

                // Save Royalty
                if (dof::exists_<String>(&reseller_shop.id, game_id)) {
                    coin::join(
                        dof::borrow_mut<String, Coin<PROI>>(&mut reseller_shop.id, game_id),
                        royalty
                    );
                } else {
                    dof::add(&mut reseller_shop.id, game_id, royalty);
                };
            }
        };
        
        // Save paid
        if (dof::exists_<address>(&reseller_shop.id, license_key.owner)) {
            coin::join(
                dof::borrow_mut<address, Coin<PROI>>(&mut proi_shop.id, license_key.owner),
                paid
            );
        } else {
            dof::add(&mut reseller_shop.id, license_key.owner, paid);
        };

        // Transfer item
        let (_, origin_item_info) = vec_map::remove<ID, ResellerItem>(item_list, &item_id);
        let ResellerItem{
            id,
            reseller: _reseller,
            description: _description,
            price: _price,
            item: origin_license_key
        } = origin_item_info;

        origin_license_key.owner = buyer;
        transfer::transfer(origin_license_key, buyer);
        object::delete(id);

        // Emit Event
        event::emit(ResellEvent{item_id})
    }

    // Take PROI for Purchase fees
    public entry fun take_proi_for_labs(
        proi_shop: &mut ProiShop,
        cap: & ProiCap,
        ctx: &mut TxContext
    ){
        // Capability
        assert!(object::id(proi_shop) == cap.for, ENotPublisher);

        // Purchase fees
        let storage = &mut proi_shop.purchase_fee_storage;
        let amount = balance::value(&storage.fees);

        assert!(amount > 0, ENoPROIs);

        let proi = coin::take(&mut storage.fees, amount, ctx);
        transfer::public_transfer(proi, tx_context::sender(ctx))
    }

    // Take PROI for game publisher
    public entry fun take_proi_for_publisher(
        proi_shop: &mut ProiShop,
        cap: & GamePubCap,
        game_id_bytes: vector<u8>,
        ctx: &mut TxContext
    ){
        // Capability
        let game_id = string::utf8(game_id_bytes);
        let game = get_game(&proi_shop.game_list, &game_id);
        assert!(object::id(game) == cap.for, ENotPublisher);

        // Check stored PROI
        assert!(dof::exists_<String>(&proi_shop.id, game_id) == true, ENoPROIs);

        let proi = dof::remove<String, Coin<PROI>>(&mut proi_shop.id, game_id);
        transfer::public_transfer(proi, tx_context::sender(ctx))
    }

    // Take PROI for reseller
    public entry fun take_proi_for_reseller(
        reseller_shop: &mut ResellerShop,
        ctx: &mut TxContext
    ){
        // Check stored PROI
        let sender = tx_context::sender(ctx);
        assert!(dof::exists_<address>(&reseller_shop.id, sender) == true, ENoPROIs);

        let proi = dof::remove<address, Coin<PROI>>(&mut reseller_shop.id, sender);
        transfer::public_transfer(proi, sender)
    }

    // Take PROI for game publisher
    public entry fun take_proi_for_royalty(
        proi_shop: &mut ProiShop,
        reseller_shop: &mut ResellerShop,
        cap: & GamePubCap,
        game_id_bytes: vector<u8>,
        ctx: &mut TxContext
    ){
        // Capability
        let game_id = string::utf8(game_id_bytes);
        let game = get_game(&proi_shop.game_list, &game_id);
        assert!(object::id(game) == cap.for, ENotPublisher);

        // Check stored PROI
        assert!(dof::exists_<String>(&reseller_shop.id, game_id) == true, ENoPROIs);

        let proi = dof::remove<String, Coin<PROI>>(&mut reseller_shop.id, game_id);
        transfer::public_transfer(proi, tx_context::sender(ctx))
    }

    /// exchange usd to proi
    public fun change_price_usd_to_proi(
        usd: u64
    ): u64{
        // For testing purposes, PROI has been set to be converted to USD at a 1:1 ratio. 
        // In the future, Every day at a specified time, the PROI:USD ratio is refreshed and applied through Oracle.
        usd * proi::get_decimal()
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun get_game_for_testing(
        proi_shop: & ProiShop,
        game_id: & String
    ): &Game{
        assert!(vec_map::contains(&proi_shop.game_list, game_id) == true, ENotExistGameID);
        vec_map::get(&proi_shop.game_list, game_id)
    }

    #[test_only]
    public fun get_item_id_by_idx_for_testing(
        reseller_shop: &ResellerShop,
        idx: u64
    ): ID {
        let (_, v) = vec_map::get_entry_by_idx<ID, ResellerItem>(&reseller_shop.item_list, idx);
        object::id(v)
    }
}
