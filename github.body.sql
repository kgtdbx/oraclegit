create or replace package body github

as

	function get_account_passwd (
		github_account				in			varchar2
	)
	return varchar2

	as

		pass_out					varchar2(500) := null;

	begin

		select github_password
		into pass_out
		from github_account
		where upper(github_username) = upper(github_account);

		return pass_out;

	end get_account_passwd;

	function encode64_clob(
		content 				in 			clob
	) 
	return clob 

	is
		--the chunk size must be a multiple of 48
		chunksize 				integer := 576;
		place 					integer := 1;
		file_size 				integer;
		temp_chunk 				varchar(4000);
		out_clob 				clob;
	begin
		file_size := length(content);
		
		while (place <= file_size) loop
		       temp_chunk := substr(content, place, chunksize);
		       out_clob := out_clob  || utl_raw.cast_to_varchar2(utl_encode.base64_encode(utl_raw.cast_to_raw(temp_chunk)));
		       place := place + chunksize;
		end loop;

		return out_clob;
	end encode64_clob;

	function github_committer_hash
	return json.jsonstructobj

	as

		committer 					json.jsonstructobj;

	begin

		json.newjsonobj(committer);
		committer := json.addattr(committer, 'name', user);
		committer := json.addattr(committer, 'email', user || '@' || sys_context('USERENV', 'DB_NAME'));
		json.closejsonobj(committer);

		return committer;

	end github_committer_hash;

	procedure talk (
		github_account				in			varchar2
		, api_endpoint				in			varchar2
		, endpoint_method			in			varchar2
		, api_data					in			clob default null
	)

	as

		github_request				utl_http.req;
		github_response				utl_http.resp;
		github_result_piece			varchar2(32000);


	begin

		-- Extended error checking
		utl_http.set_response_error_check(
			enable => true
		);
		utl_http.set_detailed_excp_support(
			enable => true
		);

		utl_http.set_wallet(
			oraclegit.get_oraclegit_env('github_wallet_location')
			, oraclegit.get_oraclegit_env('github_wallet_passwd')
		);

		-- Start the request
		github_request := utl_http.begin_request(
			url => oraclegit.get_oraclegit_env('github_api_location') || api_endpoint
			, method => endpoint_method
		);

		-- Set authentication and headers
		utl_http.set_authentication(
			r => github_request
			, username => github_account
			, password => get_account_passwd(github_account)
			, scheme => 'Basic'
			, for_proxy => false
		);
		utl_http.set_header(
			r => github_request
			, name => 'User-Agent'
			, value => github_account
		);

		-- Method specific headers
		if (api_data is not null) then
			utl_http.set_header(
				r => github_request
				, name => 'Content-Type'
				, value => 'application/x-www-form-urlencoded'
			);
			utl_http.set_header(
				r => github_request
				, name => 'Content-Length'
				, value => length(api_data)
			);
			-- Write the content
			utl_http.write_text (
				r => github_request
				, data => api_data
			);
		end if;

		github_response := utl_http.get_response (
			r => github_request
		);

		-- Collect response and put into api_result
		begin
			loop
				utl_http.read_text (
					r => github_response
					, data => github_result_piece
				);
				github_api_raw_result := github_api_raw_result || github_result_piece;
			end loop;

			exception
				when utl_http.end_of_body then
					null;
				when others then
					raise;
		end;

		utl_http.end_response(
			r => github_response
		);

		github_api_parsed_result := json.string2json(github_api_raw_result);

		-- dbms_output.put_line(github_api_raw_result);

		exception
			when utl_http.http_client_error then
				dbms_output.put_line(UTL_HTTP.GET_DETAILED_SQLERRM);
				raise;
			when others then
				raise;

	end talk;

end github;
/