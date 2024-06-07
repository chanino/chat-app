import { signInWithPopup, signOut } from 'https://www.gstatic.com/firebasejs/10.11.1/firebase-auth.js';
import { auth, provider, awsConfig } from './config.js';

$(document).ready(function() {
    let userToken = null;
    let currentPage = 1;
    const pdfPrefix = 'docs_aws_amazon_com/web-application-hosting-best-practices/web-application-hosting-best-practices/';

    // Google login event
    $("#google-login").click(function() {
        signInWithPopup(auth, provider)
            .then((result) => {
                const user = result.user;
                // Update UI
                $("#google-login").hide();
                $("#user-name").text(user.displayName || user.email).show();
                $("#logout").show();
                $("#user-content").show();
                console.log('Google sign-in successful for:', user.email);

                user.getIdToken().then(function(token) {
                    userToken = token;
                    // Initialize the Cognito Identity credentials
                    AWS.config.region = awsConfig.region;
                    AWS.config.credentials = new AWS.CognitoIdentityCredentials({
                        IdentityPoolId: awsConfig.IdentityPoolId,
                        Logins: {
                            'accounts.google.com': userToken
                        }
                    });

                    AWS.config.credentials.get(function(err) {
                        if (err) {
                            console.error('Error getting AWS credentials:', err);
                        } else {
                            console.log('AWS credentials obtained:', AWS.config.credentials);
                            // Call showPdfViewer() after successfully obtaining credentials
                            showPdfViewer();
                        }
                    });
                }).catch((error) => {
                    console.error('Error getting ID token:', error.message);
                });
            }).catch((error) => {
                console.error('Error signing in with Google:', error.message);
            });
    });

    // Logout event
    $("#logout").click(function() {
        signOut(auth).then(() => {
            // Update UI
            $("#google-login").show();
            $("#user-name").hide();
            $("#logout").hide();
            $("#user-content").hide();
            userToken = null;
            AWS.config.credentials.clearCachedId();
            console.log('Logged out successfully');
        }).catch((error) => {
            console.error("Sign out failed:", error.message);
        });
    });

    // Handle URL form submission
    $("#url-form").submit(function(event) {
        event.preventDefault();
        if (!userToken) {
            alert("You must be logged in to submit a URL.");
            return;
        }

        const url = $("#url-input").val();

        $.ajax({
            url: 'https://7zl9faran2.execute-api.us-west-2.amazonaws.com/prod/message',
            type: 'POST',
            headers: {
                'Authorization': `Bearer ${userToken}`
            },
            data: JSON.stringify({
                body: JSON.stringify({ message: url })
            }),
            success: function(response) {
                console.log('URL submitted successfully:', response);
                alert('URL submitted successfully!');
            },
            error: function(xhr, status, error) {
                console.error('Error submitting URL:', error);
                alert('Error submitting URL.');
            }
        });
    });

    // Show PDF viewer
    function showPdfViewer() {
        $("#pdf-viewer").show();
        loadPage();
    }

    function loadPage() {
        const pageImageUrl = `${pdfPrefix}page-${currentPage}.png`;
        const pageTextUrl = `${pdfPrefix}page-${currentPage}.txt`;

        const s3 = new AWS.S3();

        s3.getObject({ Bucket: awsConfig.Bucket, Key: pageImageUrl }, function(err, data) {
            if (err) {
                console.error('Error loading page image:', err);
                if (err.code === 'CredentialsError') {
                    console.error('AWS credentials are missing. Please log in and try again.');
                }
                $("#page-image").attr("src", "");
            } else {
                const url = URL.createObjectURL(new Blob([data.Body], { type: data.ContentType }));
                $("#page-image").attr("src", url);
            }
        });

        s3.getObject({ Bucket: awsConfig.Bucket, Key: pageTextUrl }, function(err, data) {
            if (err) {
                console.error('Error loading page text:', err);
                if (err.code === 'CredentialsError') {
                    console.error('AWS credentials are missing. Please log in and try again.');
                }
                $("#page-text").text("Text not available.");
            } else {
                const text = new TextDecoder("utf-8").decode(data.Body);
                $("#page-text").text(text);
            }
        });
    }

    // Handle previous page button click
    $("#prev-page").click(function() {
        if (currentPage > 1) {
            currentPage--;
            loadPage();
        }
    });

    // Handle next page button click
    $("#next-page").click(function() {
        currentPage++;
        loadPage();
    });
});