import { signInWithPopup, signOut } from 'https://www.gstatic.com/firebasejs/10.11.1/firebase-auth.js';
import { auth, provider } from './config.js';

$(document).ready(function() {
    let userToken = null;
    let currentPage = 1;
    const pdfPrefix = 'docs_aws_amazon_com/web-application-hosting-best-practices/web-application-hosting-best-practices/';

    // Configure AWS Amplify
    AWSAmplify.default.configure({
        Auth: {
            identityPoolId: 'YOUR_IDENTITY_POOL_ID', // Replace with your Cognito Identity Pool ID
            region: 'us-west-2', // Replace with your region
            userPoolId: 'YOUR_USER_POOL_ID', // Replace with your Cognito User Pool ID
            userPoolWebClientId: 'YOUR_USER_POOL_CLIENT_ID', // Replace with your Cognito User Pool Client ID
        },
        Storage: {
            AWSS3: {
                bucket: 'chat-bro-userdata', // Replace with your S3 bucket name
                region: 'us-west-2', // Replace with your region
            }
        }
    });

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

                // Get the ID token of the logged-in user
                user.getIdToken().then(function(token) {
                    userToken = token;
                    console.log(token);
                    // Authenticate with Cognito
                    AWS.config.credentials = new AWS.CognitoIdentityCredentials({
                        IdentityPoolId: 'YOUR_IDENTITY_POOL_ID', // Replace with your Identity Pool ID
                        Logins: {
                            'accounts.google.com': token
                        }
                    });
                    AWS.config.credentials.refresh((error) => {
                        if (error) {
                            console.error('Error refreshing credentials:', error);
                        } else {
                            console.log('Successfully authenticated with Cognito');
                        }
                    });
                }).catch((error) => {
                    console.error('Error getting ID token:', error.message);
                });
            }).catch((error) => {
                console.error('Google sign-in error:', error.message);
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

    // Load a specific page of the PDF
    function loadPage() {
        const pageImageKey = `${pdfPrefix}page-${currentPage}.png`;
        const pageTextKey = `${pdfPrefix}page-${currentPage}.txt`;

        // Get the image from S3
        AWSAmplify.Storage.get(pageImageKey, { level: 'public' })
            .then(result => {
                $("#page-image").attr("src", result);
            })
            .catch(err => {
                console.error('Error getting image from S3:', err);
                $("#page-image").attr("src", '');
            });

        // Get the text from S3
        AWSAmplify.Storage.get(pageTextKey, { level: 'public', download: true })
            .then(result => {
                const reader = new FileReader();
                reader.onload = (e) => {
                    $("#page-text").text(e.target.result);
                };
                reader.readAsText(result.Body);
            })
            .catch(err => {
                console.error('Error getting text from S3:', err);
                $("#page-text").text('Text not available.');
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

    // Initially show the hardcoded PDF viewer
    showPdfViewer();
});