#!/bin/bash

protocol_list=(
    TUIC
    Trojan
    Hysteria2
    VMess-WS
    VMess-TCP
    VMess-HTTP
    VMess-QUIC
    Shadowsocks
    VMess-H2-TLS
    VMess-WS-TLS
    VLESS-H2-TLS
    VLESS-WS-TLS
    Trojan-H2-TLS
    Trojan-WS-TLS
    VMess-HTTPUpgrade-TLS
    VLESS-HTTPUpgrade-TLS
    Trojan-HTTPUpgrade-TLS
    VLESS-REALITY
    VLESS-HTTP2-REALITY
    AnyTLS
    # Direct
    Socks
)
# ss2022 系方法（随机默认只从这里取，不再依赖下标顺序）
ss_method_2022=(
    2022-blake3-aes-128-gcm
    2022-blake3-aes-256-gcm
    2022-blake3-chacha20-poly1305
)
ss_method_legacy=(
    aes-128-gcm
    aes-256-gcm
    chacha20-ietf-poly1305
    xchacha20-ietf-poly1305
)
ss_method_list=("${ss_method_2022[@]}" "${ss_method_legacy[@]}")
mainmenu=(
    "添加配置"
    "更改配置"
    "查看配置"
    "删除配置"
    "运行管理"
    "更新"
    "卸载"
    "其他"
)
change_list=(
    "更改协议"
    "更改端口"
    "更改域名"
    "更改路径"
    "更改密码"
    "更改 UUID"
    "更改加密方式"
    "更改目标地址"
    "更改目标端口"
    "更改密钥"
    "更改 SNI (serverName)"
    "更改伪装网站"
    "更改用户名 (Username)"
    "更改端口/进口IP/出口IP"
)
servername_list=(
    www.amazon.com
    www.ebay.com
    www.paypal.com
    www.cloudflare.com
    dash.cloudflare.com
    aws.amazon.com
)
# 协议别名表（一次性构建; 新增别名只需在此加一行）
# 注意必须用 -g: 本文件被 install.sh/入口脚本的 load() 函数内 source 时,
# 顶层 declare 不加 -g 会变成 load() 的局部变量, 函数返回即丢失
declare -gA PROTOCOL_ALIAS=(
    [ws]=VMess-WS [tcp]=VMess-TCP [quic]=VMess-QUIC [http]=VMess-HTTP
    [wss]=VMess-WS-TLS [h2]=VMess-H2-TLS [hu]=VMess-HTTPUpgrade-TLS
    [vws]=VLESS-WS-TLS [vh2]=VLESS-H2-TLS [vhu]=VLESS-HTTPUpgrade-TLS
    [tws]=Trojan-WS-TLS [th2]=Trojan-H2-TLS [thu]=Trojan-HTTPUpgrade-TLS
    [r]=VLESS-REALITY [reality]=VLESS-REALITY [rh2]=VLESS-HTTP2-REALITY
    [ss]=Shadowsocks [door]=Direct [direct]=Direct [tuic]=TUIC
    [hy]=Hysteria2 [hy2]=Hysteria2 [anytls]=AnyTLS [socks]=Socks [trojan]=Trojan
)

# shuf fallback for systems without shuf (e.g., Alpine BusyBox)
if ! type -P shuf &>/dev/null; then
    shuf() {
        local min max n
        while [[ $# -gt 0 ]]; do
            case $1 in
            -i) IFS=- read min max <<<"$2"; shift 2 ;;
            -n) n=$2; shift 2 ;;
            esac
        done
        [[ $max ]] || return 1 # 未传 -i 时不做除零运算
        echo $(( RANDOM % (max - min + 1) + min ))
    }
fi

msg() {
    echo -e "$@"
}

msg_ul() {
    echo -e "\e[4m$@\e[0m"
}

# 按固定列宽打印 "标签=值" 信息行 (代替 info_list + 数字索引 + tab 宽度 hack)
show_info() {
    local kv label val
    for kv in "$@"; do
        label=${kv%%=*}
        val=${kv#*=}
        printf "%-24s= \e[${is_color}m%s\e[0m\n" "$label" "$val"
    done
}

print_no_auto_tls_hint() {
    msg "\e[41m no-auto-tls 帮助(help)\e[0m: $(msg_ul https://233boy.com/$is_core/no-auto-tls/)\n"
}

# pause
pause() {
    echo
    echo -ne "按 $(_green Enter 回车键) 继续, 或按 $(_red Ctrl + C) 取消."
    read -rs -d $'\n'
    echo
}

get_uuid() {
    tmp_uuid=$(cat /proc/sys/kernel/random/uuid)
}

get_ip() {
    [[ $ip || $is_no_auto_tls || $is_gen || $is_dont_get_ip ]] && return
    export "$(_wget -4 -qO- $IP_API | grep ip=)" &>/dev/null
    [[ ! $ip ]] && export "$(_wget -6 -qO- $IP_API | grep ip=)" &>/dev/null
    [[ ! $ip ]] && {
        err "获取服务器 IP 失败.."
    }
}

# ====================== 可定制配置区 ======================
# 独立运行守卫（防止 core.sh 被直接 bash 时 is_core 尚未赋值）
: "${is_core:=sing-box}"
# 用户自定义覆盖（可选）: 可覆盖下方默认值以及上方列表变量（ss_method_list 等）
# 覆盖示例: echo 'PORT_MIN=10000' > /etc/$is_core/script.conf
[[ -f /etc/$is_core/script.conf ]] && . /etc/$is_core/script.conf
# 默认值（若未被 script.conf 覆盖）
: "${PORT_MIN:=445}"
: "${PORT_MAX:=65535}"
: "${PORT_TRY_MAX:=233}"
: "${MENU_MAX:=233}"
: "${NTP_SERVER:=time.apple.com}"
: "${LOG_PATH:=/var/log/$is_core/access.log}"
: "${IP_API:=https://one.one.one.one/cdn-cgi/trace}"
: "${DNS_API:=https://one.one.one.one/dns-query}"

# 派生表与随机默认值（在 script.conf 之后构建, 覆盖 ss_method_list/servername_list 即可生效）
# 同上: -g 保证在 load() 函数内 source 时仍是全局
declare -gA SS_METHOD_ALIAS
for m in "${ss_method_list[@]}"; do SS_METHOD_ALIAS[${m,,}]=$m; done
is_random_ss_method=${ss_method_2022[$(shuf -i 0-$((${#ss_method_2022[@]} - 1)) -n1)]} # random only use ss2022
is_random_servername=${servername_list[$(shuf -i 0-$((${#servername_list[@]} - 1)) -n1)]}
# =========================================================

get_port() {
    is_count=0
    while :; do
        ((is_count++))
        if [[ $is_count -ge $PORT_TRY_MAX ]]; then
            err "自动获取可用端口失败次数达到 $PORT_TRY_MAX 次, 请检查端口占用情况."
        fi
        tmp_port=$(shuf -i ${PORT_MIN}-${PORT_MAX} -n 1)
        is_test port_used "$tmp_port" && continue
        [[ $tmp_port == $port ]] && continue
        break
    done
}

get_pbk() {
    is_tmp_pbk=($($is_core_bin generate reality-keypair | sed 's/.*://'))
    is_public_key=${is_tmp_pbk[1]}
    is_private_key=${is_tmp_pbk[0]}
}

# build the json fragment to bind the outbound to a specified IP (IPv4/IPv6)
# 片段内使用 $bind_ip 引用, 由 create server 统一 --arg bind_ip 注入
set_bind_json() {
    is_bind_json_addr=
    [[ $is_bind_ip ]] && {
        if [[ $is_bind_ip =~ : ]]; then
            is_bind_json_addr=",inet6_bind_address:\$bind_ip"
        else
            is_bind_json_addr=",inet4_bind_address:\$bind_ip"
        fi
    }
}

# validate IPv4 / IPv6 address format (loose check)
validate_ip() {
    local ip=$1 o
    # IPv4
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local o; for o in ${ip//./ }; do
            [[ 10#$o -gt 255 ]] && return 1
        done
        return 0
    fi
    # IPv6 (loose: at least one colon, only hex digits and colons)
    [[ $ip == *:* && $ip =~ ^[0-9A-Fa-f:]+$ ]] && return 0
    return 1
}

# unified input validators; on failure set VALIDATE_ERR and return 1
validate_port() {
    local p=$1 mode=${2:-ask}
    ! is_test port "$p" && { VALIDATE_ERR="请输入正确的端口, 可选(1-65535)"; return 1; }
    [[ $mode == door ]] && return 0
    [[ $mode == change ]] && { [[ $p == 443 || $p == "$port" ]] && return 0; }
    is_test port_used "$p" && { VALIDATE_ERR="无法使用 ($p) 端口."; return 1; }
    return 0
}
validate_uuid() {
    is_test uuid "$1" && return 0
    [[ ! $tmp_uuid ]] && get_uuid
    VALIDATE_ERR="请输入正确的 UUID, 例如: $tmp_uuid"
    return 1
}
validate_path() {
    is_test path "$1" && return 0
    [[ ! $tmp_uuid ]] && get_uuid
    VALIDATE_ERR="请输入正确的路径, 例如: /$tmp_uuid"
    return 1
}

# ask_value 用的校验包装器 (校验函数需显式传入, 不再按变量名嗅探)
v_port() { validate_port "$1" ask; }
v_port_door() { validate_port "$1" door; }

# 判断 is_core_ver 是否 >= 指定版本 (用法: core_at_least 1.12.0)
core_at_least() {
    local have=${is_core_ver#v} want=${1#v}
    local -a h w
    IFS=. read -ra h <<<"$have"
    IFS=. read -ra w <<<"$want"
    local i
    for i in 0 1 2; do
        (( ${h[i]:-0} > ${w[i]:-0} )) && return 0
        (( ${h[i]:-0} < ${w[i]:-0} )) && return 1
    done
    return 0
}

# change 分支统一的不支持提示 (文案取自 change_list)
unsupported() { err "($is_config_file) 不支持$1."; }

# extracted utility helpers (reusable, no change to existing flows)

bracket_v6() { [[ $1 == *:* && $1 != \[* ]] && echo "[$1]" || echo "$1"; }

# 测试运行单个服务：未运行时拉起并打印失败信息
_test_run_one() {
    local name=$1 bin=$2 svc=$3 cfg=$4
    if [[ ! $(pgrep -f "$bin") ]]; then
        _yellow "\n测试运行 $name ..\n"
        manage start $svc &>/dev/null
        if [[ $is_run_fail == $svc ]]; then
            _red "$name 运行失败信息:"
            if [[ $cfg ]]; then
                "$bin" run $cfg # cfg 为整串参数, 此处有意保留分词
            else
                "$bin" run --config "$is_caddyfile"
            fi
        else
            _green "\n测试通过, 已启动 $name ..\n"
        fi
    else
        _green "\n$name 正在运行, 跳过测试\n"
    fi
}

_wait_core_alive() {
    local i
    for ((i = 0; i < 25; i++)); do # 轮询最多 5 秒, 避免固定 sleep 在慢机上误报、快机上白等
        pgrep -f "$is_run_bin" &>/dev/null && return 0
        sleep 0.2
    done
    is_run_fail=${is_do_name_msg,,}
    [[ ! $is_no_manage_msg ]] && {
        msg
        warn "($is_do_msg) $is_do_name_msg 失败"
        _yellow "检测到运行失败, 自动执行测试运行."
        get test-run
        _yellow "测试结束, 请按 Enter 退出."
    }
    return 1
}

# 从配置文件提取字段到全局变量 (key=value 形式, 顺序无关, 值可含空格/=)
load_config_vars() {
    local f=$is_conf_dir/$1 data k v
    # 复位上次加载的字段, 避免串配置
    unset is_protocol port is_listen_ip uuid password username ss_method ss_password \
        door_port door_addr net_type path host is_servername is_private_key \
        is_public_key is_bind_ip
    data=$(jq -r '
        def p($k;$v): if $v == null then empty else "\($k)=\($v|tostring)" end;
        .inbounds[0] as $i |
        p("is_protocol";    $i.type),
        p("port";           $i.listen_port),
        p("is_listen_ip";   $i.listen),
        p("uuid";           $i.users[0].uuid),
        p("password";       $i.users[0].password // $i.password),
        p("username";       $i.users[0].username),
        p("ss_method";      $i.method),
        p("door_port";      $i.override_port),
        p("door_addr";      $i.override_address),
        p("net_type";       $i.transport.type),
        p("path";           $i.transport.path),
        p("host";           $i.transport.headers.host),
        p("is_servername";  $i.tls.server_name),
        p("is_private_key"; $i.tls.reality.private_key),
        p("is_public_key";  .outbounds[1].tag),
        p("is_bind4";       .outbounds[0].inet4_bind_address),
        p("is_bind6";       .outbounds[0].inet6_bind_address)
    ' "$f" 2>/dev/null) || err "无法读取此文件: $1"
    while IFS='=' read -r k v; do
        [[ $v == null || -z $v ]] && continue
        case $k in
        is_bind4 | is_bind6) is_bind_ip=$v ;;
        *)                   printf -v "$k" '%s' "$v" ;;
        esac
    done <<<"$data"
    is_loaded_info=1 # 标记: 已从配置文件加载过字段 (get protocol 的 vmess-tcp 分支依赖此标记)
}

# rebuild route rules into the MAIN config.json.
# sing-box merges the -C directory for inbounds/outbounds only, NOT route blocks,
# so the route rules must live in the main config.json. Each reality inbound is
# routed to its own bound direct outbound (direct_<port>).
build_route_json() {
    [[ ! -d $is_conf_dir ]] && return
    [[ ! -f $is_config_json ]] && return
    is_route_rules=
    for f in "$is_conf_dir"/*.json; do
        [[ -f "$f" ]] || continue
        [[ "$f" == *route.json ]] && continue
        is_in_tag=$(jq -r '.inbounds[0].tag' "$f" 2>/dev/null)
        is_out_tag=$(jq -r '.outbounds[]?.tag | select(test("^direct_[0-9]+$"))' "$f" 2>/dev/null | head -1)
        [[ $is_in_tag && $is_out_tag ]] && {
            is_route_rules="$is_route_rules,{\"inbound\":[\"$is_in_tag\"],\"outbound\":\"$is_out_tag\"}"
        }
    done
    if [[ $is_route_rules ]]; then
        is_route_json=$(jq -n "{rules:[${is_route_rules#,}],final:\"direct\"}")
        jq --argjson r "$is_route_json" '.route = $r' "$is_config_json" >"$is_config_json.tmp" && mv "$is_config_json.tmp" "$is_config_json"
    else
        jq 'del(.route)' "$is_config_json" >"$is_config_json.tmp" && mv "$is_config_json.tmp" "$is_config_json"
    fi
}

show_list() {
    local i=1
    for item in "$@"; do
        printf "  %2d) %s\n" "$i" "$item"
        ((i++))
    done
}

is_test() {
    local v=$2
    case $1 in
    port)       [[ $v =~ ^[0-9]+$ ]] && (( 10#$v >= 1 && 10#$v <= 65535 )) ;;
    port_used)  is_port_used "$v" && [[ ! $is_cant_test_port ]] ;;
    path)       [[ $v =~ ^/[[:alnum:]_./-]+$ ]] ;;
    uuid)       [[ $v =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] ;;
    esac
}

is_port_used() {
    local port=$1
    if [[ -z $is_used_port ]]; then
        if type -P ss &>/dev/null; then
            is_used_port="$(ss -tlnpH 2>/dev/null; ss -ulnH 2>/dev/null)"
        elif type -P netstat &>/dev/null; then
            is_used_port="$(netstat -tnlp 2>/dev/null; netstat -unlp 2>/dev/null)"
        else
            is_cant_test_port=1
            msg "$is_warn 无法检测端口是否可用."
            msg "请执行: $(_yellow "${cmd} update -y; ${cmd} install net-tools -y") 来修复此问题."
            return 1
        fi
        is_used_port="$(sed -n 's/.*:\([0-9]\+\).*/\1/p' <<<"$is_used_port" | sort -nu)"
    fi
    grep -qx "$port" <<<"$is_used_port"
}

# ======================== 交互原语 ========================
# 用 printf -v 回写调用方变量 (兼容 bash 4.2, 不用 nameref), 校验函数显式传入

# 字符串输入: $1=变量名 $2=提示语 $3=默认值(空输入时使用; 传空则重新输入) $4=校验函数(可选, 失败读 VALIDATE_ERR)
ask_value() {
    local var=$1 prompt=$2 def=$3 check=$4 input
    while :; do
        echo -ne "$prompt"
        read -r input
        [[ -z $input && $def ]] && input=$def
        [[ -z $input ]] && continue
        if [[ ! $check ]] || "$check" "$input"; then
            printf -v "$var" '%s' "$input"
            msg "使用: ${!var}"
            return 0
        fi
        msg "$is_err $VALIDATE_ERR"
    done
}

# 列表选择: $1=值变量 $2=序号变量(""=不写) $3=标题(""=不打印) $4=输入提示(""=默认) $5=默认值
#   $5 传 "exit" → 空输入退出脚本 (主菜单用); 传其他值 → 空输入取该默认值; 传空 → 空输入重新输入
# 其余参数 = 选项列表
ask_menu() {
    local val_var=$1 idx_var=$2 title=$3 prompt=$4 def=$5
    shift 5
    local opts=("$@") pick i
    [[ $title ]] && msg "$title"
    show_list "${opts[@]}"
    [[ ! $prompt ]] && prompt="请选择 [\e[91m1-${#opts[@]}\e[0m]:"
    while :; do
        echo -ne "$prompt"
        read -r pick
        if [[ -z $pick ]]; then
            if [[ $def == exit ]]; then
                exit
            elif [[ $def ]]; then
                printf -v "$val_var" '%s' "$def"
                if [[ $idx_var ]]; then
                    for i in "${!opts[@]}"; do
                        [[ ${opts[i]} == "$def" ]] && printf -v "$idx_var" '%s' "$((i + 1))" && break
                    done
                fi
                msg "选择: $def"
                return 0
            fi
            continue
        fi
        if [[ $pick =~ ^[0-9]+$ ]] && (( 10#$pick >= 1 && 10#$pick <= ${#opts[@]} )); then
            printf -v "$val_var" '%s' "${opts[10#$pick - 1]}"
            [[ $idx_var ]] && printf -v "$idx_var" '%s' "$((10#$pick))"
            msg "选择: ${!val_var}"
            return 0
        fi
        msg "输入${is_err}"
    done
}

# y 确认: 输入 y 直到确认
confirm() {
    local r
    while :; do
        echo -ne "$1"
        read -r r
        [[ $r =~ ^[Yy]$ ]] && return 0
        msg "请输入 (y)"
    done
}

# create file
_config_filename() {
    local proto=$1
    if [[ $host ]]; then
        is_config_name=$proto-${host}.json
    elif [[ $is_anytls_domain ]]; then
        is_config_name=$proto-${is_anytls_domain}.json
    else
        is_config_name=$proto-${port}.json
    fi
}

_resolve_listen() {
    if [[ $host ]]; then
        is_listen='listen: "127.0.0.1"'
    else
        is_listen='listen: "::"'
        [[ $is_listen_ip ]] && is_listen="listen: \"$is_listen_ip\""
    fi
}

select_local_ip() {
    local prompt="$1" var="$2"
    is_local_ips=()
    [[ $(type -P ip) ]] && {
        is_local_ips+=($(ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -v '^127\.0\.0\.1$'))
        is_local_ips+=($(ip -o -6 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -vE '^(fe80|::1|::)'))
    }
    [[ $(type -P hostname) ]] && is_local_ips+=($(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^127\.0\.0\.1$'))
    [[ ${#is_local_ips[@]} -gt 0 ]] && is_local_ips=($(printf '%s\n' "${is_local_ips[@]}" | awk '!seen[$0]++'))
    [[ ${#is_local_ips[@]} -eq 0 ]] && { printf -v "$var" ''; return 1; }
    is_tmp_list=("${is_local_ips[@]}")
    ask_menu "$var" "" "$prompt" "请选择序号 [1-${#is_tmp_list[@]}], 回车选择第一项(${is_tmp_list[0]}):" "${is_tmp_list[0]}" "${is_tmp_list[@]}"
}

# ======================== 配置创建 ========================
create() {
    case $1 in
    server)
        is_tls=none
        get new
        _config_filename "$2"
        _resolve_listen
        is_json_file=$is_conf_dir/$is_config_name
        # get json
        [[ $is_change || ! $json_str ]] && get protocol $2
        [[ $net == "reality" ]] && {
            set_bind_json
            # 约定：reality 公钥藏入一个假 outbound 的 tag（public_key_<key>），
            # 读回逻辑见 load_config_vars（is_public_key=${is_public_key/public_key_/}），
            # 并依赖 build_route_json 的 ^direct_[0-9]+$ 过滤不误伤该 outbound。
            is_add_public_key=",outbounds:[{tag:\"direct_$port\",type:\"direct\"${is_bind_json_addr}},{tag:\"public_key_$is_public_key\",type:\"direct\"}]"
        } || is_add_public_key=
        # 用户可控值一律走 --arg 注入, 片段内只允许出现 $var 引用, 杜绝转义/注入问题
        is_new_json=$(jq \
            --arg tag "$is_config_name" \
            --arg uuid "$uuid" \
            --arg password "$password" \
            --arg ss_method "$ss_method" \
            --arg ss_password "$ss_password" \
            --arg path "$path" \
            --arg host "$host" \
            --arg servername "$is_servername" \
            --arg private_key "$is_private_key" \
            --arg door_addr "$door_addr" \
            --arg socks_user "$is_socks_user" \
            --arg socks_pass "$is_socks_pass" \
            --arg anytls_domain "$is_anytls_domain" \
            --arg tls_key "$is_tls_key" \
            --arg tls_cer "$is_tls_cer" \
            --arg bind_ip "$is_bind_ip" \
            "{inbounds:[{tag:\$tag,type:\"$is_protocol\",$is_listen,listen_port:$port,$json_str}]$is_add_public_key}" <<<{})
        [[ $is_test_json ]] && return # tmp test
        # only show json, dont save to file.
        [[ $is_gen ]] && {
            msg
            jq <<<$is_new_json
            msg
            return
        }
        # del old file
        [[ $is_config_file ]] && is_no_del_msg=1 && del $is_config_file
        # save json to file
        cat <<<$is_new_json >"$is_json_file"
        unset is_used_port # 新端口已占用, 失效端口占用缓存
        if [[ $is_new_install ]]; then
            create config.json
        fi
        build_route_json
        # caddy auto tls
        [[ $is_caddy && $host && ! $is_no_auto_tls ]] && {
            create caddy $net
        }
        # restart core
        manage_bg restart
        ;;
    client)
        is_tls=tls
        is_client=1
        get info $2
        [[ ! $is_client_id_json ]] && err "($is_config_name) 不支持生成客户端配置."
        is_new_json=$(jq '{outbounds:[{tag:'\"$is_config_name\"',protocol:'\"$is_protocol\"','"$is_client_id_json"','"$is_stream"'}]}' <<<{})
        msg
        jq <<<$is_new_json
        msg
        ;;
    caddy)
        load caddy.sh
        [[ $is_install_caddy ]] && caddy_config new
        grep -q "$is_caddy_conf" "$is_caddyfile" 2>/dev/null || {
            msg "import $is_caddy_conf/*.conf" >>"$is_caddyfile"
        }
        [[ ! -d $is_caddy_conf ]] && mkdir -p "$is_caddy_conf"
        caddy_config $2
        manage_bg restart caddy
        ;;
    config.json)
        # 已有配置: 仅当 .ntp.enabled=true 时保留 ntp; 新配置: 仅在安装期 NTP 不可用时写入
        is_ntp=
        if [[ -f $is_config_json ]]; then
            [[ $(jq .ntp.enabled "$is_config_json" 2>/dev/null) == "true" ]] && is_ntp=',ntp:{enabled:true,server:$ntp_server}'
        elif [[ $is_ntp_on ]]; then
            is_ntp=',ntp:{enabled:true,server:$ntp_server}'
        fi
        is_server_config_json=$(jq -n \
            --arg log_path "$LOG_PATH" \
            --arg ntp_server "$NTP_SERVER" \
            "{log:{output:\$log_path,level:\"info\",timestamp:true},outbounds:[{tag:\"direct\",type:\"direct\"}]$is_ntp}")
        cat <<<$is_server_config_json >"$is_config_json"
        manage_bg restart
        ;;
    esac
}

# change config file
# ======================== 配置修改 ========================
change() {
    local v
    is_change=1
    is_dont_show_info=1
    if [[ $2 ]]; then
        err "不支持命令行参数, 请直接在菜单中选择操作."
    fi
    [[ $is_dont_auto_exit ]] && {
        get info $1
    } || {
        [[ $is_change_id ]] && {
            is_change_msg=${change_list[$is_change_id]}
            [[ $is_change_id == 'full' ]] && {
                [[ $3 ]] && is_change_msg="更改多个参数" || is_change_msg=
            }
            [[ $is_change_msg ]] && _green "\n快速执行: $is_change_msg"
        }
        info $1
        [[ $is_auto_get_config ]] && msg "\n自动选择: $is_config_file"
    }
    is_old_net=$net
    [[ $is_tcp_http ]] && net=http
    [[ $host ]] && net=$is_protocol-$net-tls
    [[ $is_reality && $net_type =~ 'http' ]] && net=rh2

    # if is_dont_show_info exist, cant show info.
    is_dont_show_info=
    # if not prefer args, show change list and then get change id.
    [[ ! $is_change_id ]] && {
        is_change_opts=()
        for v in "${is_can_change[@]}"; do
            is_change_opts+=("${change_list[$v]}")
        done
        [[ $is_reality ]] && is_change_def="${is_change_opts[0]}" || is_change_def=
        ask_menu is_change_str change_pick "\n请选择更改:\n" "" "$is_change_def" "${is_change_opts[@]}"
        [[ $change_pick ]] && is_change_id=${is_can_change[change_pick - 1]} || is_change_id=${is_can_change[0]}
    }
    case $is_change_id in
    0)
        # new protocol
        is_set_new_protocol=1
        add ${@:3}
        ;;
    1)
        # new port
        is_new_port=$3
        [[ ( $host && ! $is_caddy ) || $is_no_auto_tls ]] && err "($is_config_file) 不支持更改端口, 因为没啥意义."
        if [[ $is_new_port && ! $is_auto ]]; then
            validate_port "$is_new_port" change || err "$VALIDATE_ERR"
        fi
        [[ $is_auto ]] && get_port && is_new_port=$tmp_port
        [[ ! $is_new_port ]] && ask_value is_new_port "请输入新端口:" "" v_port
        if [[ $is_caddy && $host ]]; then
            net=$is_old_net
            is_https_port=$is_new_port
            load caddy.sh
            caddy_config $net
            manage_bg restart caddy
            info
        else
            add $net $is_new_port
        fi
        ;;
    2 | 11)
        # new host / new host (伪装网站): 两分支逻辑相同, 报错文案取自 change_list
        is_new_host=$3
        [[ ! $host ]] && unsupported "${change_list[$is_change_id]}"
        [[ ! $is_new_host ]] && ask_value is_new_host "请输入新域名:"
        old_host=$host # del old host
        add $net $is_new_host
        ;;
    3)
        # new path
        is_new_path=$3
        [[ ! $path ]] && unsupported "${change_list[$is_change_id]}"
        [[ $is_auto ]] && get_uuid && is_new_path=/$tmp_uuid
        [[ ! $is_new_path ]] && ask_value is_new_path "请输入新路径:" "" validate_path
        add $net auto auto $is_new_path
        ;;
    4)
        # new password
        is_new_pass=$3
        if [[ $ss_password || $password ]]; then
            [[ $is_auto ]] && {
                get_uuid && is_new_pass=$tmp_uuid
                [[ $ss_password ]] && is_new_pass=$(get ss2022)
            }
        else
            unsupported "${change_list[$is_change_id]}"
        fi
        [[ ! $is_new_pass ]] && ask_value is_new_pass "请输入新密码:"
        password=$is_new_pass
        ss_password=$is_new_pass
        is_socks_pass=$is_new_pass
        add $net
        ;;
    5)
        # new uuid
        is_new_uuid=$3
        [[ ! $uuid ]] && unsupported "${change_list[$is_change_id]}"
        [[ $is_auto ]] && get_uuid && is_new_uuid=$tmp_uuid
        [[ ! $is_new_uuid ]] && ask_value is_new_uuid "请输入新 UUID:" "" validate_uuid
        add $net auto $is_new_uuid
        ;;
    6)
        # new method
        is_new_method=$3
        [[ $net != 'ss' ]] && unsupported "${change_list[$is_change_id]}"
        [[ $is_auto ]] && is_new_method=$is_random_ss_method
        [[ ! $is_new_method ]] && {
            ask_menu ss_method "" "\n请选择加密方式:\n" "(默认\e[92m $is_random_ss_method\e[0m):" "$is_random_ss_method" "${ss_method_list[@]}"
            is_new_method=$ss_method
        }
        add $net auto auto $is_new_method
        ;;
    7)
        # new remote addr
        is_new_door_addr=$3
        [[ $net != 'direct' ]] && unsupported "${change_list[$is_change_id]}"
        [[ ! $is_new_door_addr ]] && ask_value is_new_door_addr "请输入新的目标地址:"
        door_addr=$is_new_door_addr
        add $net
        ;;
    8)
        # new remote port
        is_new_door_port=$3
        [[ $net != 'direct' ]] && unsupported "${change_list[$is_change_id]}"
        [[ ! $is_new_door_port ]] && {
            ask_value door_port "请输入新的目标端口:" "" v_port_door
            is_new_door_port=$door_port
        }
        add $net auto auto $is_new_door_port
        ;;
    9)
        # new is_private_key is_public_key
        is_new_private_key=$3
        is_new_public_key=$4
        [[ ! $is_reality ]] && err "($is_config_file) 不支持更改密钥."
        if [[ $is_auto ]]; then
            get_pbk
            add $net
        else
            [[ $is_new_private_key && ! $is_new_public_key ]] && {
                err "无法找到 Public key."
            }
            [[ ! $is_new_private_key ]] && ask_value is_new_private_key "请输入新 Private key:"
            [[ ! $is_new_public_key ]] && ask_value is_new_public_key "请输入新 Public key:"
            if [[ $is_new_private_key == $is_new_public_key ]]; then
                err "Private key 和 Public key 不能一样."
            fi
            is_tmp_json=$is_conf_dir/$is_config_file-$uuid
            jq --arg pk "$is_new_private_key" '.inbounds[0].tls.reality.private_key = $pk' \
                "$is_conf_dir/$is_config_file" >"$is_tmp_json" 2>/dev/null
            $is_core_bin check -c "$is_tmp_json" &>/dev/null || {
                is_key_err=1
                is_key_err_msg="Private key 无法通过测试."
            }
            jq --arg pk "$is_new_public_key" '.inbounds[0].tls.reality.private_key = $pk' \
                "$is_tmp_json" >"$is_tmp_json.2" 2>/dev/null && mv -f "$is_tmp_json.2" "$is_tmp_json"
            $is_core_bin check -c "$is_tmp_json" &>/dev/null || {
                is_key_err=1
                is_key_err_msg+="Public key 无法通过测试."
            }
            rm -f "$is_tmp_json"
            [[ $is_key_err ]] && err $is_key_err_msg
            is_private_key=$is_new_private_key
            is_public_key=$is_new_public_key
            is_test_json=
            add $net
        fi
        ;;
    10)
        # new serverName
        is_new_servername=$3
        [[ ! $is_reality ]] && unsupported "${change_list[$is_change_id]}"
        [[ $is_auto ]] && is_new_servername=$is_random_servername
        [[ ! $is_new_servername ]] && ask_value is_new_servername "请输入新的 serverName:"
        is_servername=$is_new_servername
        add $net
        ;;
    12)
        # new socks user
        [[ ! $is_socks_user ]] && unsupported "${change_list[$is_change_id]}"
        ask_value is_socks_user "请输入新用户名 (Username):"
        add $net
        ;;
    13)
        # 更改端口 / 进口IP / 出口IP (combined network settings)
        [[ ! $is_reality ]] && unsupported "此更改"
        # 1) 新端口
        is_new_port=$3
        if [[ $is_new_port && ! $is_auto ]]; then
            validate_port "$is_new_port" change || err "$VALIDATE_ERR"
        fi
        [[ ! $is_new_port ]] && {
            [[ $is_auto ]] && get_port && is_new_port=$tmp_port
            [[ ! $is_new_port ]] && ask_value is_new_port "请输入新端口 (当前: $port, 回车保持):" "$port" v_port
        }
        [[ $is_new_port && $is_new_port != $port ]] && port=$is_new_port
        # 2) 新进口IP (inbound listen)
        select_local_ip "\n请选择进口 IP (本机可用地址):\n" is_new_listen_ip
        is_listen_ip=$is_new_listen_ip
        select_local_ip "\n请选择出口 IP (本机可用地址):\n" is_new_bind_ip
        if [[ $is_new_bind_ip ]]; then
            validate_ip "$is_new_bind_ip" || err "($is_new_bind_ip) 不是有效的 IPv4 / IPv6 地址."
        fi
        is_bind_ip=$is_new_bind_ip
        add $net
        ;;
    esac
    [[ $is_config_name ]] && is_config_file=$is_config_name
}

# delete config.
# ======================== 配置删除 ========================
del() {
    # dont get ip
    is_dont_get_ip=1
    [[ $is_conf_dir_empty ]] && return # not found any json file.
    # get a config file
    [[ ! $is_config_file ]] && get info $1
    if [[ $is_config_file ]]; then
        if [[ $is_main_start && ! $is_no_del_msg ]]; then
            msg "\n是否删除配置文件?: $is_config_file"
            pause
        fi
        rm -rf "$is_conf_dir/$is_config_file"
        [[ ! $is_new_json ]] && build_route_json
        [[ ! $is_new_json ]] && manage_bg restart
        [[ ! $is_no_del_msg ]] && _green "\n已删除: $is_config_file\n"

        [[ $is_caddy ]] && {
            is_del_host=$host
            [[ $is_change ]] && is_del_host=$old_host # 换域名场景删除旧域名的 caddy 配置; old_host 为空则跳过
            [[ $is_del_host && $host != $old_host && -f "$is_caddy_conf/$is_del_host.conf" ]] && {
                rm -rf "$is_caddy_conf/$is_del_host.conf" "$is_caddy_conf/$is_del_host.conf.add"
                [[ ! $is_new_json ]] && manage_bg restart caddy
            }
        }
    fi
    if [[ ! $(ls "$is_conf_dir" | grep -E '\.json$') && ! $is_change ]]; then
        warn "当前配置目录为空! 因为你刚刚删除了最后一个配置文件."
        is_conf_dir_empty=1
    fi
    unset is_dont_get_ip
    [[ $is_dont_auto_exit ]] && unset is_config_file
}

# uninstall
uninstall() {
    if [[ $is_caddy ]]; then
        ask_menu is_do_uninstall uninstall_pick "" "" "" "卸载 $is_core_name" "卸载 ${is_core_name} & Caddy"
    else
        confirm "是否卸载 ${is_core_name}? [y]:"
    fi
    manage stop &>/dev/null
    manage disable &>/dev/null
    rm -rf "$is_core_dir" "$is_log_dir" "$is_sh_bin" "${is_sh_bin/$is_core/sb}"
    if [[ $is_systemd ]]; then
        rm -f /lib/systemd/system/$is_core.service
    elif [[ $is_openrc ]]; then
        rm -f /etc/init.d/$is_core
    fi
    sed -i -e "/^alias sb=/d" -e "/^alias ${is_core}=/d" /root/.bashrc
    # uninstall caddy; uninstall_pick 2 = 卸载 core & Caddy
    if [[ $uninstall_pick == 2 ]]; then
        manage stop caddy &>/dev/null
        manage disable caddy &>/dev/null
        if [[ $is_systemd ]]; then
            rm -rf "$is_caddy_dir" "$is_caddy_bin" /lib/systemd/system/caddy.service
        elif [[ $is_openrc ]]; then
            rm -rf "$is_caddy_dir" "$is_caddy_bin" /etc/init.d/caddy
        fi
    fi
    [[ $is_install_sh ]] && return # reinstall
    _green "\n卸载完成!"
    msg "脚本哪里需要完善? 请反馈"
    msg "反馈问题) $(msg_ul https://github.com/${is_sh_repo}/issues)\n"
}

# manage run status
manage_bg() { manage "$@" & }
manage() {
    [[ $is_dont_auto_exit ]] && return
    case $1 in
    1 | start)
        is_do=start
        is_do_msg=启动
        is_test_run=1
        ;;
    2 | stop)
        is_do=stop
        is_do_msg=停止
        ;;
    3 | r | restart)
        is_do=restart
        is_do_msg=重启
        is_test_run=1
        ;;
    *)
        is_do=$1
        is_do_msg=$1
        ;;
    esac
    case $2 in
    caddy)
        is_do_name=$2
        is_run_bin=$is_caddy_bin
        is_do_name_msg=Caddy
        ;;
    *)
        is_do_name=$is_core
        is_run_bin=$is_core_bin
        is_do_name_msg=$is_core_name
        ;;
    esac
    if [[ $is_systemd ]]; then
        systemctl $is_do $is_do_name 2>/dev/null
    elif [[ $is_openrc ]]; then
        case $is_do in
        enable)
            rc-update add $is_do_name default 2>/dev/null
            ;;
        disable)
            rc-update del $is_do_name default 2>/dev/null
            ;;
        *)
            rc-service $is_do_name $is_do 2>/dev/null
            ;;
        esac
    fi
    [[ $is_test_run && ! $is_new_install ]] && _wait_core_alive
}

# add a config
# ======================== 配置添加 ========================
add() {
    local v
    is_lower=${1,,}
    if [[ $is_lower ]]; then
        case $is_lower in
        hysteria*)
            is_new_protocol=Hysteria2
            ;;
        *)
            is_new_protocol=${PROTOCOL_ALIAS[$is_lower]}
            if [[ ! $is_new_protocol ]]; then
                for v in "${protocol_list[@]}"; do
                    [[ ${v,,} == "$is_lower" ]] && is_new_protocol=$v && break
                done
            fi
            [[ ! $is_new_protocol ]] && err "无法识别 ($1), 请使用: $is_core add [protocol] [args... | auto]"
            ;;
        esac
    fi

    # no prefer protocol
    if [[ ! $is_new_protocol ]]; then
        is_proto_opts=()
        for v in "${protocol_list[@]}"; do
            [[ $is_no_auto_tls && ! ${v,,} =~ -tls$ ]] && continue
            is_proto_opts+=("$v")
        done
        ask_menu is_new_protocol "" "\n请选择协议:\n" "" "" "${is_proto_opts[@]}"
    fi

    if [[ ${is_new_protocol,,} == 'anytls' ]]; then
        core_at_least 1.12.0 || err "当前 sing-box 版本 ($is_core_ver) 不支持 AnyTLS，请先升级 sing-box core 到 1.12.0 或更高版本。"
    fi

    case ${is_new_protocol,,} in
    *-tls)
        is_use_tls=1
        is_use_host=$2
        is_use_uuid=$3
        is_use_path=$4
        is_add_opts="[host] [uuid] [/path]"
        ;;
    vmess* | tuic*)
        is_use_port=$2
        is_use_uuid=$3
        is_add_opts="[port] [uuid]"
        ;;
    trojan* | hysteria*)
        is_use_port=$2
        is_use_pass=$3
        is_add_opts="[port] [password]"
        ;;
    *reality*)
        is_reality=1
        is_use_port=$2
        is_use_uuid=$3
        is_use_servername=$4
        is_add_opts="[port] [uuid] [sni]"
        ;;
    shadowsocks)
        is_use_port=$2
        is_use_pass=$3
        is_use_method=$4
        is_add_opts="[port] [password] [method]"
        ;;
    direct)
        is_use_port=$2
        is_use_door_addr=$3
        is_use_door_port=$4
        is_add_opts="[port] [remote_addr] [remote_port]"
        ;;
    anytls*)
        is_use_port=$2
        is_use_pass=$3
        [[ $4 ]] && is_anytls_domain=$4
        is_add_opts="[port] [password] [domain]"
        ;;
    socks)
        is_socks=1
        is_use_port=$2
        is_use_socks_user=$3
        is_use_socks_pass=$4
        is_add_opts="[port] [username] [password]"
        ;;
    esac

    [[ $1 && ! $is_change ]] && {
        msg "\n使用协议: $is_new_protocol"
        # err msg tips
        is_err_tips="\n\n请使用: $(_green $is_core add $1 $is_add_opts) 来添加 $is_new_protocol 配置"
    }

    # remove old protocol args
    if [[ $is_set_new_protocol ]]; then
        case $is_old_net in
        h2 | ws | httpupgrade)
            old_host=$host
            [[ ! $is_use_tls ]] && unset host is_no_auto_tls
            ;;
        reality)
            net_type=
            [[ ! ${is_new_protocol,,} =~ reality ]] && is_reality=
            ;;
        ss)
            is_test uuid "$ss_password" && uuid=$ss_password
            ;;
        esac
        ! is_test uuid "$uuid" && uuid=
        is_test uuid "$password" && uuid=$password
    fi

    # no-auto-tls only use h2,ws,grpc
    if [[ $is_no_auto_tls && ! $is_use_tls ]]; then
        err "$is_new_protocol 不支持手动配置 tls."
    fi

    # prefer args.
    if [[ $2 ]]; then
        for v in is_use_port is_use_uuid is_use_host is_use_path is_use_pass is_use_method is_use_door_addr is_use_door_port; do
            [[ ${!v} == 'auto' ]] && unset $v
        done

        if [[ $is_use_port ]]; then
            validate_port "$is_use_port" "${is_gen:+door}" || err "$VALIDATE_ERR $is_err_tips"
            port=$is_use_port
        fi
        if [[ $is_use_door_port ]]; then
            validate_port "$is_use_door_port" door || err "$VALIDATE_ERR $is_err_tips"
            door_port=$is_use_door_port
        fi
        if [[ $is_use_uuid ]]; then
            ! is_test uuid "$is_use_uuid" && {
                err "($is_use_uuid) 不是一个有效的 UUID. $is_err_tips"
            }
            uuid=$is_use_uuid
        fi
        if [[ $is_use_path ]]; then
            ! is_test path "$is_use_path" && {
                err "($is_use_path) 不是有效的路径. $is_err_tips"
            }
            path=$is_use_path
        fi
        if [[ $is_use_method ]]; then
            is_tmp_use_name=加密方式
            is_tmp_use_type=${SS_METHOD_ALIAS[${is_use_method,,}]:-}
            [[ ! ${is_tmp_use_type} ]] && {
                warn "(${is_use_method}) 不是一个可用的${is_tmp_use_name}."
                msg "${is_tmp_use_name}可用如下: "
                for v in "${ss_method_list[@]}"; do
                    msg "\t\t$v"
                done
                msg "$is_err_tips\n"
                return 1
            }
            ss_method=$is_tmp_use_type
        fi
        [[ $is_use_pass ]] && ss_password=$is_use_pass && password=$is_use_pass
        [[ $is_use_host ]] && host=$is_use_host
        [[ $is_use_door_addr ]] && door_addr=$is_use_door_addr
        [[ $is_use_servername ]] && is_servername=$is_use_servername
        [[ $is_use_socks_user ]] && is_socks_user=$is_use_socks_user
        [[ $is_use_socks_pass ]] && is_socks_pass=$is_use_socks_pass
    fi

    # anytls with domain (ACME TLS)
    if [[ $is_anytls_domain && ! $is_change && ! $is_gen ]]; then
        get_ip
        host=$is_anytls_domain
        get host-test
        host=
    fi

    if [[ $is_use_tls ]]; then
        if [[ ! $is_no_auto_tls && ! $is_caddy && ! $is_gen && ! $is_dont_test_host ]]; then
            # test auto tls
            { is_test port_used 80 || is_test port_used 443; } && {
                get_port
                is_http_port=$tmp_port
                get_port
                is_https_port=$tmp_port
                warn "端口 (80 或 443) 已经被占用, 你也可以考虑使用 no-auto-tls"
                print_no_auto_tls_hint
                msg "\n Caddy 将使用非标准端口实现自动配置 TLS, HTTP:$is_http_port HTTPS:$is_https_port\n"
                msg "请确定是否继续???"
                pause
            }
            is_install_caddy=1
        fi
        # set host
        [[ ! $host ]] && ask_value host "请输入域名:"
        # test host dns
        get host-test
    else
        # for main menu start, dont auto create args
        if [[ $is_main_start ]]; then

            # set port
            [[ ! $port ]] && ask_value port "请输入端口:" "" v_port

            case ${is_new_protocol,,} in
            socks)
                # set user
                [[ ! $is_socks_user ]] && ask_value is_socks_user "请设置用户名:"
                # set password
                [[ ! $is_socks_pass ]] && ask_value is_socks_pass "请设置密码:"
                ;;
            shadowsocks)
                # set method
                [[ ! $ss_method ]] && ask_menu ss_method "" "\n请选择加密方式:\n" "(默认\e[92m $is_random_ss_method\e[0m):" "$is_random_ss_method" "${ss_method_list[@]}"
                # set password
                [[ ! $ss_password ]] && ask_value ss_password "请设置密码:"
                ;;
            esac

        fi
    fi

    # Dokodemo-Door
    if [[ $is_new_protocol == 'Direct' ]]; then
        # set remote addr
        [[ ! $door_addr ]] && ask_value door_addr "请输入目标地址:"
        # set remote port
        [[ ! $door_port ]] && ask_value door_port "请输入目标端口:" "" v_port_door
    fi

    # Shadowsocks 2022
    if [[ $ss_method == *2022* ]]; then
        # test ss2022 password
        [[ $ss_password ]] && {
            is_test_json=1
            create server Shadowsocks
            [[ ! $tmp_uuid ]] && get_uuid
            is_test_json_save=$is_conf_dir/tmp-test-$tmp_uuid
            cat <<<"$is_new_json" >$is_test_json_save
            $is_core_bin check -c $is_test_json_save &>/dev/null
            if [[ $? != 0 ]]; then
                warn "Shadowsocks 协议 ($ss_method) 不支持使用密码 ($(_red_bg $ss_password))\n\n你可以使用命令: $(_green $is_core ss2022) 生成支持的密码.\n\n脚本将自动创建可用密码:)"
                ss_password=
                # create new json.
                json_str=
            fi
            is_test_json=
            rm -f $is_test_json_save
        }

    fi

    # install caddy
    if [[ $is_install_caddy ]]; then
        get install-caddy
    fi

    # create json
    create server $is_new_protocol

    # show config info.
    info $is_config_name
}

# get config info
# or somes required args
get() {
    case $1 in
    addr)
        if [[ $is_listen_ip && $is_listen_ip != '::' ]]; then
            is_addr=$is_listen_ip
            is_addr=$(bracket_v6 "$is_addr")
        else
            is_addr=$host
            [[ ! $is_addr ]] && {
                get_ip
                is_addr=$ip
                is_addr=$(bracket_v6 "$ip")
            }
        fi
        ;;
    new)
        [[ ! $host ]] && get_ip
        [[ ! $port ]] && get_port && port=$tmp_port
        [[ ! $uuid ]] && get_uuid && uuid=$tmp_uuid
        ;;
    file)
        is_file_str=$2
        [[ ! $is_file_str ]] && is_file_str='.json$'
        readarray -t is_all_json <<<"$(ls "$is_conf_dir" | grep -E -i "$is_file_str" | sed '/^route\.json$/d' | head -$MENU_MAX)" # limit max $MENU_MAX lines for show.
        [[ ! $is_all_json ]] && err "无法找到相关的配置文件: $2"
        [[ ${#is_all_json[@]} -eq 1 ]] && is_config_file=$is_all_json && is_auto_get_config=1
        [[ ! $is_config_file ]] && {
            [[ $is_dont_auto_exit ]] && return
            ask_menu is_config_file "" "\n请选择配置:\n" "" "" "${is_all_json[@]}"
        }
        ;;
    info)
        get file $2
        if [[ $is_config_file ]]; then
            is_json_str=$(cat "$is_conf_dir/$is_config_file") || err "无法读取此文件: $is_config_file"
            load_config_vars "$is_config_file"

            if [[ $is_private_key ]]; then
                is_reality=1
                net_type+=reality
                # 从假 outbound tag 中抠回 reality 公钥（见 create 时的约定）
                is_public_key=${is_public_key/public_key_/}
            fi
            is_socks_user=$username
            is_socks_pass=$password

            # extract anytls ACME domain
            [[ $is_protocol == 'anytls' ]] && {
                is_anytls_domain=$(jq -r '(.inbounds[0].tls.certificate_provider.domain[0] // .inbounds[0].tls.acme.domain[0]) // empty' <<<$is_json_str 2>/dev/null)
            }

            is_config_name=$is_config_file

            if [[ $is_caddy && $host && -f $is_caddy_conf/$host.conf ]]; then
                is_tmp_https_port=$(grep -E -o "$host:[1-9][0-9]?+" "$is_caddy_conf/$host.conf" | sed s/.*://)
            fi
            if [[ $host && ! -f $is_caddy_conf/$host.conf ]]; then
                is_no_auto_tls=1
            fi
            [[ $is_tmp_https_port ]] && is_https_port=$is_tmp_https_port
            [[ $is_client && $host ]] && port=$is_https_port
            get protocol $is_protocol-$net_type
        fi
        ;;
    protocol)
        get addr # get host or server ip
        is_lower=${2,,}
        net=
        is_path_host_json= # 复位: 更改协议时防止残留上一配置的 path/host 头
        # 以下 json 片段内只允许 $var 引用, 由 create server 统一 --arg 注入, 不再内插字面值
        is_users="users:[{uuid:\$uuid}]"
        is_tls_json='tls:{enabled:true,alpn:["h3"],key_path:$tls_key,certificate_path:$tls_cer}'
        case $is_lower in
        vmess*)
            is_protocol=vmess
            [[ $is_lower =~ "tcp" || ! $net_type && $is_loaded_info ]] && net=tcp && json_str=$is_users
            ;;
        vless*)
            is_protocol=vless
            ;;
        tuic*)
            net=tuic
            is_protocol=$net
            [[ ! $password ]] && password=$uuid
            is_users="users:[{uuid:\$uuid,password:\$password}]"
            json_str="$is_users,congestion_control:\"bbr\",$is_tls_json"
            ;;
        trojan*)
            is_protocol=trojan
            [[ ! $password ]] && password=$uuid
            is_users="users:[{password:\$password}]"
            [[ ! $host ]] && {
                net=trojan
                json_str="$is_users,${is_tls_json/alpn\:\[\"h3\"\],/}"
            }
            ;;
        hysteria2*)
            net=hysteria2
            is_protocol=$net
            [[ ! $password ]] && password=$uuid
            json_str="users:[{password:\$password}],$is_tls_json"
            ;;
        shadowsocks*)
            net=ss
            is_protocol=shadowsocks
            [[ ! $ss_method ]] && ss_method=$is_random_ss_method
            [[ ! $ss_password ]] && {
                ss_password=$uuid
                [[ $ss_method == *2022* ]] && ss_password=$(get ss2022)
            }
            json_str="method:\$ss_method,password:\$ss_password"
            ;;
        direct*)
            net=direct
            is_protocol=$net
            json_str="override_port:$door_port,override_address:\$door_addr"
            ;;
        anytls*)
            net=anytls
            is_protocol=$net
            [[ ! $password ]] && password=$uuid
            is_users="users:[{password:\$password}]"
            if [[ $is_anytls_domain ]]; then
                # sing-box >= 1.14.0 uses certificate_provider; older uses acme
                if core_at_least 1.14.0; then
                    is_anytls_tls="tls:{enabled:true,certificate_provider:{type:\"acme\",domain:[\$anytls_domain]}}"
                else
                    is_anytls_tls="tls:{enabled:true,acme:{domain:[\$anytls_domain]}}"
                fi
            else
                is_anytls_tls="${is_tls_json/alpn\:\[\"h3\"\],/}"
            fi
            json_str="$is_users,$is_anytls_tls"
            ;;
        socks*)
            net=socks
            is_protocol=$net
            [[ ! $is_socks_user ]] && is_socks_user=233boy
            [[ ! $is_socks_pass ]] && is_socks_pass=$uuid
            json_str="users:[{username:\$socks_user,password:\$socks_pass}]"
            ;;
        *)
            err "无法识别协议: $is_config_file"
            ;;
        esac
        [[ $net ]] && return # if net exist, dont need more json args
        [[ $host && $is_lower =~ "tls" ]] && {
            [[ ! $path ]] && path="/$uuid"
            is_path_host_json=",path:\$path,headers:{host:\$host}"
        }
        case $is_lower in
        *quic*)
            net=quic
            is_json_add="$is_tls_json,transport:{type:\"$net\"}"
            ;;
        *ws*)
            net=ws
            is_json_add="transport:{type:\"$net\"$is_path_host_json,early_data_header_name:\"Sec-WebSocket-Protocol\"}"
            ;;
        *reality*)
            net=reality
            [[ ! $is_servername ]] && is_servername=$is_random_servername
            [[ ! $is_private_key ]] && get_pbk
            is_json_add="tls:{enabled:true,server_name:\$servername,reality:{enabled:true,handshake:{server:\$servername,server_port:443},private_key:\$private_key,short_id:[\"\"]}}"
            [[ $is_lower =~ "http" ]] && {
                is_json_add="$is_json_add,transport:{type:\"http\"}"
            } || {
                is_users=${is_users/uuid/flow:\"xtls-rprx-vision\",uuid}
            }
            ;;
        *http* | *h2*)
            net=http
            [[ $is_lower =~ "up" ]] && net=httpupgrade
            is_json_add="transport:{type:\"$net\"$is_path_host_json}"
            [[ $is_lower =~ "h2" || ! $is_lower =~ "httpupgrade" && $host ]] && {
                net=h2
                is_json_add="${is_tls_json/alpn\:\[\"h3\"\],/},$is_json_add"
            }
            ;;
        *)
            err "无法识别传输协议: $is_config_file"
            ;;
        esac
        json_str="$is_users,$is_json_add"
        ;;
    host-test) # test host dns record; for auto *tls required.
        [[ $is_no_auto_tls || $is_gen || $is_dont_test_host ]] && return
        get_ip
        get ping
        if [[ $is_host_dns != *"$ip"* ]]; then
            msg "\n请将 ($(_red_bg $host)) 解析到 ($(_red_bg $ip))"
            msg "\n如果使用 Cloudflare, 在 DNS 那; 关闭 (Proxy status / 代理状态), 即是 (DNS only / 仅限 DNS)"
            confirm "我已经确定解析 [y]:"
            get ping
            if [[ $is_host_dns != *"$ip"* ]]; then
                _cyan "\n测试结果: $is_host_dns"
                err "域名 ($host) 没有解析到 ($ip)"
            fi
        fi
        ;;
    ssss | ss2022)
        if [[ $ss_method == *128* ]]; then
            $is_core_bin generate rand 16 --base64
        else
            $is_core_bin generate rand 32 --base64
        fi
        ;;
    ping)
        is_dns_type="a"
        [[ $ip == *:* ]] && is_dns_type="aaaa"
        is_host_dns=$(_wget -qO- --header="accept: application/dns-json" "$DNS_API?name=$host&type=$is_dns_type")
        ;;
    install-caddy)
        _green "\n安装 Caddy 实现自动配置 TLS.\n"
        load download.sh
        download caddy
        load systemd.sh
        install_service caddy &>/dev/null
        is_caddy=1
        _green "安装 Caddy 成功.\n"
        ;;
    reinstall)
        is_install_sh=$(cat $is_sh_dir/install.sh)
        uninstall
        bash <<<$is_install_sh
        ;;
    test-run)
        if [[ $is_systemd ]]; then
            systemctl list-units --full -all &>/dev/null
            [[ $? != 0 ]] && {
                _yellow "\n无法执行测试, 请检查 systemctl 状态.\n"
                return
            }
        fi
        is_no_manage_msg=1
        _test_run_one "$is_core_name" "$is_core_bin" "$is_core" "-c $is_config_json -C $is_conf_dir"
        [[ $is_caddy ]] && _test_run_one "Caddy" "$is_caddy_bin" "caddy"
        ;;
    esac
}

# show info
# ======================== 配置展示 ========================
info() {
    if [[ ! $is_protocol ]]; then
        get info $1
    fi
    is_color=44
    case $net in
    ws | tcp | h2 | quic | http*)
        if [[ $host ]]; then
            is_color=45
            is_can_change=(0 1 2 3 5)
            is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$is_https_port" "用户ID=$uuid" "传输协议=$net" "伪装域名=$host" "路径=$path" "TLS=tls")
            [[ $is_protocol == 'vmess' ]] && {
                is_vmess_url=$(jq -c '{v:2,ps:'\"$net-$host\"',add:'\"$is_addr\"',port:'\"$is_https_port\"',id:'\"$uuid\"',aid:"0",net:'\"$net\"',host:'\"$host\"',path:'\"$path\"',tls:'\"tls\"'}' <<<{})
                is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
            } || {
                [[ $is_protocol == "trojan" ]] && {
                    uuid=$password
                    is_can_change=(0 1 2 3 4)
                    is_show[3]="密码=$password"
                }
                is_url="$is_protocol://$uuid@$host:$is_https_port?encryption=none&security=tls&type=$net&host=$host&path=$path#$net-$host"
            }
            [[ $is_caddy ]] && is_can_change+=(11)
        else
            is_type=none
            is_quic_add=
            is_can_change=(0 1 5)
            is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "用户ID=$uuid" "传输协议=$net")
            [[ $net == "http" ]] && {
                net=tcp
                is_type=http
                is_tcp_http=1
                is_show[4]="传输协议=tcp http"
                is_show+=("伪装类型=http")
            }
            [[ $net == "quic" ]] && {
                is_insecure=1
                is_show+=("TLS=tls" "Alpn=h3" "跳过证书验证=true")
                is_quic_add=",tls:\"tls\",alpn:\"h3\"" # cant add allowInsecure
            }
            is_vmess_url=$(jq -c "{v:2,ps:\"${net}-$is_addr\",add:\"$is_addr\",port:\"$port\",id:\"$uuid\",aid:\"0\",net:\"$net\",type:\"$is_type\"$is_quic_add}" <<<{})
            is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
        fi
        ;;
    ss)
        is_can_change=(0 1 4 6)
        is_url="ss://$(echo -n ${ss_method}:${ss_password} | base64 -w 0)@${is_addr}:${port}#$net-${is_addr}"
        is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "密码=$ss_password" "加密方式=$ss_method")
        ;;
    trojan)
        is_insecure=1
        is_can_change=(0 1 4)
        is_url="$is_protocol://$password@$is_addr:$port?type=tcp&security=tls&insecure=1&allowInsecure=1#$net-$is_addr"
        is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "密码=$password" "传输协议=tcp" "TLS=tls" "跳过证书验证=true")
        ;;
    hy*)
        is_can_change=(0 1 4)
        # fix xray core for client use.
        is_sha256=$(openssl x509 -noout -fingerprint -sha256 -in $is_core_dir/bin/tls.cer | sed 's/.*=//;s/://g')
        is_url="$is_protocol://$password@$is_addr:$port?alpn=h3&insecure=1&allowInsecure=1&pinSHA256=$is_sha256#$net-$is_addr"
        is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "密码=$password" "TLS=tls" "Alpn=h3" "跳过证书验证=true (设置, 固定证书>证书指纹(SHA-256): $is_sha256)")
        ;;
    tuic)
        is_insecure=1
        is_can_change=(0 1 4 5)
        is_url="$is_protocol://$uuid:$password@$is_addr:$port?alpn=h3&insecure=1&allowInsecure=1&congestion_control=bbr#$net-$is_addr"
        is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "用户ID=$uuid" "密码=$password" "TLS=tls" "Alpn=h3" "跳过证书验证=true" "拥塞控制=bbr")
        ;;
    reality)
        is_color=41
        is_can_change=(13 0 5 9 10)
        is_flow=xtls-rprx-vision
        is_net_type=tcp
        is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "用户ID=$uuid")
        if [[ $net_type =~ "http" || ${is_new_protocol,,} =~ "http" ]]; then
            is_flow=
            is_net_type=h2
            is_show+=("传输协议=$is_net_type")
        else
            is_show+=("流控=$is_flow" "传输协议=$is_net_type")
        fi
        is_show+=("TLS=reality" "SNI=$is_servername" "指纹=chrome" "公钥=$is_public_key" "进口IP=$is_listen_ip" "出口IP=$is_bind_ip")
        is_url="$is_protocol://$uuid@$is_addr:$port?encryption=none&security=reality&flow=$is_flow&type=$is_net_type&sni=$is_servername&pbk=$is_public_key&fp=chrome#$net-$is_addr"
        ;;
    anytls)
        is_can_change=(0 1 4)
        if [[ $is_anytls_domain ]]; then
            is_show=("协议=$is_protocol" "地址=$is_anytls_domain" "端口=$port" "密码=$password" "TLS=tls")
            is_url="anytls://$password@$is_anytls_domain:$port#$net-$is_anytls_domain"
        else
            is_insecure=1
            is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "密码=$password" "TLS=tls" "跳过证书验证=true")
            is_url="anytls://$password@$is_addr:$port?insecure=1&allowInsecure=1#$net-$is_addr"
        fi
        ;;
    direct)
        is_can_change=(0 1 7 8)
        is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "目标地址=$door_addr" "目标端口=$door_port")
        ;;
    socks)
        is_can_change=(0 1 12 4)
        is_show=("协议=$is_protocol" "地址=$is_addr" "端口=$port" "用户名=$is_socks_user" "密码=$is_socks_pass")
        is_url="socks://$(echo -n ${is_socks_user}:${is_socks_pass} | base64 -w 0)@${is_addr}:${port}#$net-${is_addr}"
        ;;
    esac
    [[ $is_dont_show_info || $is_gen || $is_dont_auto_exit ]] && return # dont show info
    msg "-------------- $is_config_name -------------"
    show_info "${is_show[@]}"
    if [[ $is_url ]]; then
        msg "------------- 链接 (URL) -------------"
        msg "\e[4;${is_color}m${is_url}\e[0m"
        [[ $is_insecure ]] && {
            warn "某些客户端如(V2rayN 等)导入URL需手动将: 跳过证书验证(allowInsecure) 设置为 true, 或打开: 允许不安全的连接"
        }
    fi
    if [[ $is_no_auto_tls ]]; then
        msg "------------- no-auto-tls INFO -------------"
        msg "端口(port): $port"
        msg "路径(path): $path"
        print_no_auto_tls_hint
    fi
    footer_msg
}

# footer msg
footer_msg() {
    [[ $is_core_stop && ! $is_new_json ]] && warn "$is_core_name 当前处于停止状态."
    [[ $is_caddy_stop && $host ]] && warn "Caddy 当前处于停止状态."
    msg "------------- END -------------"
}

# update core, sh, caddy
update() {
    case $1 in
    1 | core | $is_core)
        is_update_name=core
        is_show_name=$is_core_name
        is_run_ver=v${is_core_ver##* }
        is_update_repo=$is_core_repo
        ;;
    2 | sh)
        is_update_name=sh
        is_show_name="$is_core_name 脚本"
        is_run_ver=$is_sh_ver
        is_update_repo=$is_sh_repo
        ;;
    3 | caddy)
        [[ ! $is_caddy ]] && err "不支持更新 Caddy."
        is_update_name=caddy
        is_show_name="Caddy"
        is_run_ver=$is_caddy_ver
        is_update_repo=$is_caddy_repo
        ;;
    *)
        err "无法识别 ($1), 请使用: $is_core update [core | sh | caddy] [ver]"
        ;;
    esac
    [[ $2 ]] && is_new_ver=v${2#v}
    [[ $is_run_ver == $is_new_ver ]] && {
        msg "\n自定义版本和当前 $is_show_name 版本一样, 无需更新.\n"
        exit
    }
    load download.sh
    if [[ $is_new_ver ]]; then
        msg "\n使用自定义版本更新 $is_show_name: $(_green $is_new_ver)\n"
    else
        get_latest_version $is_update_name
        [[ $is_run_ver == $latest_ver ]] && {
            msg "\n$is_show_name 当前已经是最新版本了.\n"
            exit
        }
        msg "\n发现 $is_show_name 新版本: $(_green $latest_ver)\n"
        is_new_ver=$latest_ver
    fi
    download $is_update_name $is_new_ver
    msg "更新成功, 当前 $is_show_name 版本: $(_green $is_new_ver)\n"
    msg "$(_green 请查看更新说明: https://github.com/$is_update_repo/releases/tag/$is_new_ver)\n"
    [[ $is_update_name != 'sh' ]] && manage_bg restart $is_update_name
}

# main menu; if no prefer args.
is_main_menu() {
    msg "\n------------- $is_core_name script $is_sh_ver -------------"
    msg "$is_core_name $is_core_ver: $is_core_status"
    is_main_start=1
    ask_menu is_main_pick main_pick "" "" exit "${mainmenu[@]}" # 空输入退出
    case $main_pick in
    1)
        add
        ;;
    2)
        change
        ;;
    3)
        info
        ;;
    4)
        del
        ;;
    5)
        ask_menu is_do_manage manage_pick "" "" "" 启动 停止 重启
        manage_bg $manage_pick
        msg "\n管理状态执行: $(_green $is_do_manage)\n"
        ;;
    6)
        is_tmp_list=("更新$is_core_name" "更新脚本")
        [[ $is_caddy ]] && is_tmp_list+=("更新Caddy")
        ask_menu is_do_update update_pick "\n请选择更新:\n" "" "" "${is_tmp_list[@]}"
        update $update_pick
        ;;
    7)
        uninstall
        ;;
    8)
        ask_menu is_do_other other_pick "" "" "" 启用BBR 查看日志 测试运行 重装脚本 设置DNS
        case $other_pick in
        1)
            load bbr.sh
            _try_enable_bbr
            ;;
        2)
            load log.sh
            log_set
            ;;
        3)
            get test-run
            ;;
        4)
            get reinstall
            ;;
        5)
            load dns.sh
            dns_set
            ;;
        esac
        ;;
    esac
}

# check prefer args, if not exist prefer args and show main menu
# ======================== 入口 ========================
main() {
    # 并发保护: 同一时刻只允许一个实例修改配置 (fd 持锁至进程退出; 无 flock 或无 /run/lock 的系统自动跳过)
    if [[ ! $is_locked && -d /run/lock && $(type -P flock) ]]; then
        exec 9>"/run/lock/$is_core-script.lock"
        flock -n 9 || err "另一个 $is_core 脚本实例正在运行."
        is_locked=1
    fi
    is_main_menu
}

_myself=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
_invoker=$(readlink -f "$0" 2>/dev/null || echo "$0")
[[ "$_myself" == "$_invoker" ]] && main "$@"
